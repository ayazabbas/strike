// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "pyth-lazer-sdk/IPythLazer.sol";
import "pyth-lazer-sdk/PythLazerLib.sol";
import "pyth-lazer-sdk/PythLazerStructs.sol";
import "./ITypes.sol";
import "./MarketFactory.sol";

/// @title PythResolver
/// @notice Resolves binary outcome markets using Pyth Lazer price feeds.
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

    IPythLazer public immutable pythLazer;
    MarketFactory public immutable factory;

    /// @notice Confidence threshold in bps (default 100 = 1%)
    uint256 public confThresholdBps = 100;

    /// @notice Mapping from Pyth bytes32 priceId to Lazer uint32 feedId
    mapping(bytes32 => uint32) public lazerFeedId;

    /// @notice Admin address for feed ID management
    address public admin;

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
    event LazerFeedIdSet(bytes32 indexed priceId, uint32 feedId);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _pythLazer, address _factory) {
        require(_pythLazer != address(0), "PythResolver: zero pyth");
        require(_factory != address(0), "PythResolver: zero factory");
        pythLazer = IPythLazer(_pythLazer);
        factory = MarketFactory(payable(_factory));
        admin = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    modifier onlyAdmin() {
        require(msg.sender == admin, "PythResolver: not admin");
        _;
    }

    /// @notice Map a Pyth bytes32 priceId to a Lazer uint32 feedId.
    function setLazerFeedId(bytes32 priceId, uint32 feedId) external onlyAdmin {
        lazerFeedId[priceId] = feedId;
        emit LazerFeedIdSet(priceId, feedId);
    }

    // -------------------------------------------------------------------------
    // Resolution
    // -------------------------------------------------------------------------

    /// @notice Submit resolution for a market. Permissionless.
    /// @param factoryMarketId The market to resolve.
    /// @param update Pyth Lazer signed update bytes.
    function resolveMarket(uint256 factoryMarketId, bytes calldata update)
        external
        payable
    {
        // Validate market state and extract feed parameters
        (uint32 feedId, uint256 expiryTime) = _validateAndPrepare(factoryMarketId);

        // Verify update via Pyth Lazer and extract price data
        uint256 fee = pythLazer.verification_fee();
        (int64 price, uint256 publishTime) = _verifyAndExtract(update, feedId, expiryTime, fee);

        // Apply resolution or challenge
        _applyResolution(factoryMarketId, price, publishTime);

        // Refund excess ETH
        if (msg.value > fee) {
            (bool ok, ) = msg.sender.call{value: msg.value - fee}("");
            require(ok, "PythResolver: refund failed");
        }
    }

    /// @dev Validate market state and auto-close if needed. Returns feedId and expiryTime.
    function _validateAndPrepare(uint256 factoryMarketId)
        internal
        returns (uint32 feedId, uint256 expiryTime)
    {
        bytes32 priceId;
        address creator;
        MarketState state;
        (priceId, expiryTime, , creator, state, , , ) = factory.marketMeta(factoryMarketId);

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

        feedId = lazerFeedId[priceId];
        require(feedId != 0, "PythResolver: no feed ID mapped");
    }

    /// @dev Verify Lazer update, parse payload, extract and validate price.
    function _verifyAndExtract(
        bytes calldata update,
        uint32 feedId,
        uint256 expiryTime,
        uint256 fee
    )
        internal
        returns (int64 price, uint256 publishTime)
    {
        (bytes memory payload, ) = pythLazer.verifyUpdate{value: fee}(update);

        PythLazerStructs.Update memory parsed =
            PythLazerLib.parseUpdateFromPayload(payload);

        uint64 conf;
        (price, conf, publishTime) = _extractFeed(parsed, feedId, expiryTime);

        _checkConfidence(price, conf);
    }

    /// @dev Apply first resolution or challenge to pending resolution.
    function _applyResolution(
        uint256 factoryMarketId,
        int64 price,
        uint256 publishTime
    ) internal {
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

    /// @dev Extract price, confidence, and timestamp from a parsed Lazer update.
    ///      Validates that the timestamp falls within the fallback windows.
    function _extractFeed(
        PythLazerStructs.Update memory update,
        uint32 feedId,
        uint256 expiryTime
    )
        internal
        pure
        returns (int64 price, uint64 conf, uint256 publishTime)
    {
        uint256 timestamp = uint256(update.timestamp);

        // Timestamp must be within the fallback windows
        require(
            timestamp >= expiryTime
                && timestamp <= expiryTime + MAX_FALLBACK_WINDOWS * FALLBACK_WINDOW,
            "PythResolver: no valid price in any window"
        );

        // Find matching feed by feedId
        for (uint256 i = 0; i < update.feeds.length; i++) {
            if (PythLazerLib.getFeedId(update.feeds[i]) == feedId) {
                require(
                    PythLazerLib.hasPrice(update.feeds[i]),
                    "PythResolver: price not available"
                );

                price = PythLazerLib.getPrice(update.feeds[i]);

                // Confidence is optional in Lazer updates
                if (PythLazerLib.hasConfidence(update.feeds[i])) {
                    conf = PythLazerLib.getConfidence(update.feeds[i]);
                }

                publishTime = timestamp;
                return (price, conf, publishTime);
            }
        }

        revert("PythResolver: feed not found in update");
    }

    /// @dev Reject if confidence is too wide.
    function _checkConfidence(int64 price, uint64 conf) internal view {
        if (conf == 0) return; // no confidence data, skip check
        uint256 absPrice = price >= 0 ? uint256(uint64(price)) : uint256(uint64(-price));
        uint256 maxConf = (absPrice * confThresholdBps) / 10000;
        require(uint256(conf) <= maxConf, "PythResolver: confidence too wide");
    }
}
