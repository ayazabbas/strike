// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ITypes.sol";
import "./MarketFactory.sol";

/// @title PythResolver
/// @notice Resolves binary outcome markets using Pyth Core price feeds (pull oracle).
///         Resolution is permissionless — anyone can submit price data.
///         Uses a finality gate: resolution sets pendingResolution, then
///         finalizeResolution() is callable after FINALITY_BLOCKS blocks.
///         During finality, challengers can submit alternative data;
///         earliest valid publishTime wins.
contract PythResolver is ReentrancyGuard {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant FINALITY_PERIOD = 90; // seconds
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

    /// @notice Admin address for configuration
    address public admin;

    /// @notice Pending admin for two-step transfer
    address public pendingAdmin;

    /// @notice Pending resolution data
    struct PendingResolution {
        int64 price;
        uint256 publishTime;
        uint256 resolvedAtTimestamp;
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
        factory = MarketFactory(_factory);
        admin = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    modifier onlyAdmin() {
        require(msg.sender == admin, "PythResolver: not admin");
        _;
    }

    function setConfThreshold(uint256 newBps) external onlyAdmin {
        require(newBps >= 10, "PythResolver: threshold too low");
        require(newBps <= 10000, "PythResolver: bps exceeds 10000");
        confThresholdBps = newBps;
    }

    /// @notice Begin two-step admin transfer.
    function setPendingAdmin(address _pendingAdmin) external onlyAdmin {
        pendingAdmin = _pendingAdmin;
    }

    /// @notice Accept admin role (must be called by pendingAdmin).
    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "PythResolver: not pending admin");
        admin = pendingAdmin;
        pendingAdmin = address(0);
    }

    // -------------------------------------------------------------------------
    // Resolution
    // -------------------------------------------------------------------------

    /// @notice Submit resolution for a market. Permissionless.
    /// @param factoryMarketId The market to resolve.
    /// @param priceUpdateData Pyth price update data from Hermes API.
    function resolveMarket(uint256 factoryMarketId, bytes[] calldata priceUpdateData)
        external
        payable
        nonReentrant
    {
        // Validate market state and get priceId + expiryTime
        (bytes32 priceId, uint256 expiryTime) = _validateAndPrepare(factoryMarketId);

        // Parse price from the update data within the valid time window.
        // Uses parsePriceFeedUpdates (not updatePriceFeeds) so challengers
        // can submit earlier publishTimes that wouldn't overwrite the on-chain price.
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "PythResolver: insufficient fee");

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = priceId;

        PythStructs.PriceFeed[] memory feeds = pyth.parsePriceFeedUpdates{value: fee}(
            priceUpdateData,
            ids,
            uint64(expiryTime),
            uint64(expiryTime + MAX_FALLBACK_WINDOWS * FALLBACK_WINDOW)
        );

        // Refund excess
        if (msg.value > fee) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - fee}("");
            require(ok, "PythResolver: refund failed");
        }

        PythStructs.Price memory p = feeds[0].price;

        // Check confidence
        _checkConfidence(p.price, p.conf);

        // Apply resolution or challenge
        _applyResolution(factoryMarketId, p.price, p.publishTime);
    }

    /// @notice Get the Pyth update fee for given price update data.
    function getPythUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint256) {
        return pyth.getUpdateFee(priceUpdateData);
    }

    /// @dev Validate market state and auto-close if needed. Returns priceId and expiryTime.
    function _validateAndPrepare(uint256 factoryMarketId)
        internal
        returns (bytes32 priceId, uint256 expiryTime)
    {
        address creator;
        MarketState state;
        (priceId, , expiryTime, creator, state, , , , , ) = factory.marketMeta(factoryMarketId);

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
    }

    /// @dev Apply first resolution or challenge to pending resolution.
    function _applyResolution(
        uint256 factoryMarketId,
        int64 price,
        uint256 publishTime
    ) internal {
        PendingResolution storage pending = pendingResolutions[factoryMarketId];

        if (pending.resolvedAtTimestamp == 0) {
            // First resolution submission
            pending.price = price;
            pending.publishTime = publishTime;
            pending.resolvedAtTimestamp = block.timestamp;
            pending.resolver = msg.sender;
            pending.finalized = false;

            factory.setResolving(factoryMarketId);

            emit ResolutionSubmitted(factoryMarketId, price, publishTime, msg.sender);
        } else {
            // Challenge: during finality wait, submit alternative data
            require(!pending.finalized, "PythResolver: already finalized");
            require(
                block.timestamp < pending.resolvedAtTimestamp + FINALITY_PERIOD,
                "PythResolver: finality passed"
            );

            // Earliest valid publishTime wins
            require(publishTime < pending.publishTime, "PythResolver: not earlier");

            // Challenge must change the outcome
            (, int64 strikePrice,,,,,,,, ) = factory.marketMeta(factoryMarketId);
            bool currentOutcome = pending.price >= strikePrice;
            bool newOutcome = price >= strikePrice;
            require(currentOutcome != newOutcome, "PythResolver: outcome unchanged");

            pending.price = price;
            pending.publishTime = publishTime;
            pending.resolver = msg.sender;
            // Do NOT reset resolvedAtTimestamp — finality timer keeps running

            emit ResolutionChallenged(factoryMarketId, price, publishTime, msg.sender);
        }
    }

    /// @notice Finalize resolution after finality gate passes.
    /// @param factoryMarketId The market to finalize.
    function finalizeResolution(uint256 factoryMarketId) external nonReentrant {
        PendingResolution storage pending = pendingResolutions[factoryMarketId];
        require(pending.resolvedAtTimestamp > 0, "PythResolver: no pending resolution");
        require(!pending.finalized, "PythResolver: already finalized");
        require(
            block.timestamp >= pending.resolvedAtTimestamp + FINALITY_PERIOD,
            "PythResolver: finality not reached"
        );

        pending.finalized = true;

        // Determine outcome: price >= strikePrice → YES wins
        (, int64 strikePrice,,,,,,,, ) = factory.marketMeta(factoryMarketId);
        bool outcomeYes = pending.price >= strikePrice;

        factory.setResolved(factoryMarketId, outcomeYes, pending.price);

        emit ResolutionFinalized(factoryMarketId, pending.price, outcomeYes, msg.sender);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Reject if confidence is too wide.
    function _checkConfidence(int64 price, uint64 conf) internal view {
        if (conf == 0) return; // no confidence data, skip check
        uint256 absPrice = price >= 0 ? uint256(uint64(price)) : uint256(uint64(-price));
        uint256 maxConf = (absPrice * confThresholdBps) / 10000;
        require(uint256(conf) <= maxConf, "PythResolver: confidence too wide");
    }
}
