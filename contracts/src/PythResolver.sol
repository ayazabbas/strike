// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "./ITypes.sol";
import "./MarketFactory.sol";

/// @title PythResolver
/// @notice Resolves binary outcome markets using Pyth price feeds.
///         Resolution is permissionless — anyone can submit price data.
///         Uses a finality gate: resolution sets pendingResolution, then
///         finalizeResolution() is callable after FINALITY_BLOCKS blocks.
///         During finality, challengers can submit alternative data;
///         earliest valid publishTime wins.
contract PythResolver {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant FINALITY_BLOCKS = 3;
    uint256 public constant FALLBACK_WINDOW = 60; // seconds per window
    uint256 public constant MAX_FALLBACK_WINDOWS = 5;
    uint256 public constant CANCEL_DEADLINE = 24 hours;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IPyth public immutable pyth;
    MarketFactory public immutable factory;

    /// @notice Confidence threshold in bps (default 100 = 1%)
    uint256 public confThresholdBps = 100;

    /// @notice Pending resolution data
    struct PendingResolution {
        int64 price;
        uint256 publishTime;
        uint256 resolvedAtBlock;
        address resolver;
        bool finalized;
    }

    /// @notice factoryMarketId => PendingResolution
    mapping(uint256 => PendingResolution) public pendingResolutions;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event ResolutionSubmitted(
        uint256 indexed factoryMarketId,
        int64 price,
        uint256 publishTime,
        address indexed resolver
    );
    event ResolutionChallenged(
        uint256 indexed factoryMarketId,
        int64 newPrice,
        uint256 newPublishTime,
        address indexed challenger
    );
    event ResolutionFinalized(
        uint256 indexed factoryMarketId,
        int64 price,
        bool outcomeYes,
        address indexed finalizer
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _pyth, address _factory) {
        require(_pyth != address(0), "PythResolver: zero pyth");
        require(_factory != address(0), "PythResolver: zero factory");
        pyth = IPyth(_pyth);
        factory = MarketFactory(payable(_factory));
    }

    // -------------------------------------------------------------------------
    // Resolution
    // -------------------------------------------------------------------------

    /// @notice Submit resolution for a market. Permissionless.
    /// @param factoryMarketId The market to resolve.
    /// @param updateData Pyth price update data.
    function resolveMarket(uint256 factoryMarketId, bytes[] calldata updateData)
        external
        payable
    {
        (
            bytes32 priceId,
            uint256 expiryTime,
            ,
            address creator,
            MarketState state,
            ,
            ,
        ) = factory.marketMeta(factoryMarketId);

        require(creator != address(0), "PythResolver: market not found");

        // Auto-close if still open and expired
        if (state == MarketState.Open && block.timestamp >= expiryTime) {
            factory.closeMarket(factoryMarketId);
            state = MarketState.Closed;
        }

        require(
            state == MarketState.Closed || state == MarketState.Resolving,
            "PythResolver: not closed"
        );

        // Parse price from updateData using fallback windows
        uint256 fee = pyth.getUpdateFee(updateData);
        (int64 price, uint256 publishTime, uint64 conf) =
            _parsePriceFromUpdate(updateData, priceId, expiryTime, fee);

        // Confidence check: conf <= confThresholdBps * abs(price) / 10000
        _checkConfidence(price, conf);

        PendingResolution storage pending = pendingResolutions[factoryMarketId];

        if (pending.resolvedAtBlock == 0) {
            // First resolution submission
            pending.price = price;
            pending.publishTime = publishTime;
            pending.resolvedAtBlock = block.number;
            pending.resolver = msg.sender;
            pending.finalized = false;

            factory.setResolving(factoryMarketId);

            emit ResolutionSubmitted(factoryMarketId, price, publishTime, msg.sender);
        } else {
            // Challenge: during finality wait, submit alternative data
            require(!pending.finalized, "PythResolver: already finalized");
            require(block.number < pending.resolvedAtBlock + FINALITY_BLOCKS, "PythResolver: finality passed");

            // Earliest valid publishTime wins
            require(publishTime < pending.publishTime, "PythResolver: not earlier");

            pending.price = price;
            pending.publishTime = publishTime;
            pending.resolver = msg.sender;
            // Reset finality block
            pending.resolvedAtBlock = block.number;

            emit ResolutionChallenged(factoryMarketId, price, publishTime, msg.sender);
        }

        // Refund excess ETH
        if (msg.value > fee) {
            (bool ok, ) = msg.sender.call{value: msg.value - fee}("");
            require(ok, "PythResolver: refund failed");
        }
    }

    /// @notice Finalize resolution after finality gate passes.
    /// @param factoryMarketId The market to finalize.
    function finalizeResolution(uint256 factoryMarketId) external {
        PendingResolution storage pending = pendingResolutions[factoryMarketId];
        require(pending.resolvedAtBlock > 0, "PythResolver: no pending resolution");
        require(!pending.finalized, "PythResolver: already finalized");
        require(
            block.number >= pending.resolvedAtBlock + FINALITY_BLOCKS,
            "PythResolver: finality not reached"
        );

        pending.finalized = true;

        // Determine outcome: price > 0 → YES wins
        bool outcomeYes = pending.price > 0;

        factory.setResolved(factoryMarketId, outcomeYes, pending.price);
        factory.payResolverBounty(factoryMarketId, pending.resolver);

        emit ResolutionFinalized(factoryMarketId, pending.price, outcomeYes, msg.sender);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Parse price from Pyth updateData using parsePriceFeedUpdates with fallback windows.
    function _parsePriceFromUpdate(
        bytes[] calldata updateData,
        bytes32 priceId,
        uint256 expiryTime,
        uint256 fee
    )
        internal
        returns (int64 price, uint256 publishTime, uint64 conf)
    {
        bytes32[] memory priceIds = new bytes32[](1);
        priceIds[0] = priceId;

        // Try each fallback window until one succeeds
        for (uint256 w = 0; w < MAX_FALLBACK_WINDOWS; w++) {
            uint256 windowEnd = expiryTime + (w + 1) * FALLBACK_WINDOW;

            try pyth.parsePriceFeedUpdates{value: fee}(
                updateData,
                priceIds,
                uint64(expiryTime),
                uint64(windowEnd)
            ) returns (PythStructs.PriceFeed[] memory feeds) {
                PythStructs.Price memory p = feeds[0].price;
                return (p.price, p.publishTime, p.conf);
            } catch {
                continue;
            }
        }

        revert("PythResolver: no valid price in any window");
    }

    /// @dev Reject if confidence is too wide.
    function _checkConfidence(int64 price, uint64 conf) internal view {
        uint256 absPrice = price >= 0 ? uint256(uint64(price)) : uint256(uint64(-price));
        uint256 maxConf = (absPrice * confThresholdBps) / 10000;
        require(uint256(conf) <= maxConf, "PythResolver: confidence too wide");
    }
}
