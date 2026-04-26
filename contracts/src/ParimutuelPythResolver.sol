// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ParimutuelFactory.sol";
import "./ParimutuelTypes.sol";

/// @title ParimutuelPythResolver
/// @notice Resolves multi-outcome parimutuel markets from a Pyth price feed.
/// @dev `resolverConfig` is `abi.encode(bytes32 priceId, int64[] thresholds)`.
///      For N outcomes, thresholds length must be N-1 and sorted ascending.
///      Outcome = number of thresholds where `price >= threshold`.
contract ParimutuelPythResolver is ReentrancyGuard {
    uint256 public constant FINALITY_PERIOD = 90;
    uint256 public constant FALLBACK_WINDOW = 60;
    uint256 public constant MAX_FALLBACK_WINDOWS = 5;

    IPyth public immutable pyth;
    ParimutuelFactory public immutable factory;
    address public admin;
    address public pendingAdmin;
    uint256 public confThresholdBps = 100;

    struct PendingResolution {
        int64 price;
        uint256 publishTime;
        uint256 resolvedAtTimestamp;
        uint8 winningOutcomeId;
        address resolver;
        bool finalized;
    }

    mapping(uint256 => PendingResolution) public pendingResolutions;

    event ParimutuelPythResolutionSubmitted(
        uint256 indexed marketId,
        int64 price,
        uint256 publishTime,
        uint8 indexed winningOutcomeId,
        address indexed resolver
    );
    event ParimutuelPythResolutionChallenged(
        uint256 indexed marketId,
        int64 newPrice,
        uint256 newPublishTime,
        uint8 indexed newWinningOutcomeId,
        address indexed challenger
    );
    event ParimutuelPythResolutionFinalized(
        uint256 indexed marketId, int64 price, uint8 indexed winningOutcomeId, address indexed finalizer
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "ParimutuelPythResolver: not admin");
        _;
    }

    constructor(address _pyth, address _factory) {
        require(_pyth != address(0), "ParimutuelPythResolver: zero pyth");
        require(_factory != address(0), "ParimutuelPythResolver: zero factory");
        pyth = IPyth(_pyth);
        factory = ParimutuelFactory(_factory);
        admin = msg.sender;
    }

    function setConfThreshold(uint256 newBps) external onlyAdmin {
        require(newBps >= 10, "ParimutuelPythResolver: threshold too low");
        require(newBps <= 10_000, "ParimutuelPythResolver: bps exceeds 10000");
        confThresholdBps = newBps;
    }

    function setPendingAdmin(address _pendingAdmin) external onlyAdmin {
        pendingAdmin = _pendingAdmin;
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "ParimutuelPythResolver: not pending admin");
        admin = pendingAdmin;
        pendingAdmin = address(0);
    }

    function resolveMarket(uint256 marketId, bytes[] calldata priceUpdateData) external payable nonReentrant {
        ParimutuelMarket memory market = _validateAndPrepare(marketId);
        (bytes32 priceId, int64[] memory thresholds) = _decodeConfig(market);

        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "ParimutuelPythResolver: insufficient fee");

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = priceId;
        PythStructs.PriceFeed[] memory feeds = pyth.parsePriceFeedUpdates{value: fee}(
            priceUpdateData,
            ids,
            uint64(market.closeTime),
            uint64(uint256(market.closeTime) + MAX_FALLBACK_WINDOWS * FALLBACK_WINDOW)
        );

        if (msg.value > fee) {
            (bool ok,) = payable(msg.sender).call{value: msg.value - fee}("");
            require(ok, "ParimutuelPythResolver: refund failed");
        }

        PythStructs.Price memory p = feeds[0].price;
        _checkConfidence(p.price, p.conf);
        uint8 winningOutcomeId = _outcomeForPrice(p.price, thresholds);
        _applyResolution(marketId, p.price, p.publishTime, winningOutcomeId);
    }

    function getPythUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint256) {
        return pyth.getUpdateFee(priceUpdateData);
    }

    function finalizeResolution(uint256 marketId) external nonReentrant {
        PendingResolution storage pending = pendingResolutions[marketId];
        require(pending.resolvedAtTimestamp > 0, "ParimutuelPythResolver: no pending resolution");
        require(!pending.finalized, "ParimutuelPythResolver: already finalized");
        require(
            block.timestamp >= pending.resolvedAtTimestamp + FINALITY_PERIOD,
            "ParimutuelPythResolver: finality not reached"
        );

        pending.finalized = true;
        factory.resolveFromResolver(marketId, pending.winningOutcomeId);
        emit ParimutuelPythResolutionFinalized(marketId, pending.price, pending.winningOutcomeId, msg.sender);
    }

    function _validateAndPrepare(uint256 marketId) internal returns (ParimutuelMarket memory market) {
        market = factory.getMarket(marketId);
        require(
            factory.currentResolverType(marketId) == ParimutuelResolverType.Pyth,
            "ParimutuelPythResolver: wrong resolver"
        );

        if (market.state == ParimutuelMarketState.Open && block.timestamp >= market.closeTime) {
            factory.closeMarket(marketId);
            market.state = ParimutuelMarketState.Closed;
        }
        require(
            market.state == ParimutuelMarketState.Closed || market.state == ParimutuelMarketState.Resolving,
            "ParimutuelPythResolver: market not closed"
        );
        if (market.state == ParimutuelMarketState.Closed) {
            factory.requestResolution(marketId);
        }
    }

    function _applyResolution(uint256 marketId, int64 price, uint256 publishTime, uint8 winningOutcomeId) internal {
        PendingResolution storage pending = pendingResolutions[marketId];
        if (pending.resolvedAtTimestamp == 0) {
            pending.price = price;
            pending.publishTime = publishTime;
            pending.resolvedAtTimestamp = block.timestamp;
            pending.winningOutcomeId = winningOutcomeId;
            pending.resolver = msg.sender;
            pending.finalized = false;
            emit ParimutuelPythResolutionSubmitted(marketId, price, publishTime, winningOutcomeId, msg.sender);
            return;
        }

        require(!pending.finalized, "ParimutuelPythResolver: already finalized");
        require(
            block.timestamp < pending.resolvedAtTimestamp + FINALITY_PERIOD, "ParimutuelPythResolver: finality passed"
        );
        require(publishTime < pending.publishTime, "ParimutuelPythResolver: not earlier");
        require(winningOutcomeId != pending.winningOutcomeId, "ParimutuelPythResolver: outcome unchanged");

        pending.price = price;
        pending.publishTime = publishTime;
        pending.winningOutcomeId = winningOutcomeId;
        pending.resolver = msg.sender;
        emit ParimutuelPythResolutionChallenged(marketId, price, publishTime, winningOutcomeId, msg.sender);
    }

    function _decodeConfig(ParimutuelMarket memory market)
        internal
        pure
        returns (bytes32 priceId, int64[] memory thresholds)
    {
        (priceId, thresholds) = abi.decode(market.resolverConfig, (bytes32, int64[]));
        require(priceId != bytes32(0), "ParimutuelPythResolver: zero priceId");
        require(thresholds.length + 1 == market.outcomeCount, "ParimutuelPythResolver: invalid thresholds");
        for (uint256 i = 1; i < thresholds.length; i++) {
            require(thresholds[i] > thresholds[i - 1], "ParimutuelPythResolver: unsorted thresholds");
        }
    }

    function _outcomeForPrice(int64 price, int64[] memory thresholds) internal pure returns (uint8 outcomeId) {
        for (uint256 i = 0; i < thresholds.length; i++) {
            if (price >= thresholds[i]) {
                outcomeId++;
            } else {
                break;
            }
        }
    }

    function _checkConfidence(int64 price, uint64 conf) internal view {
        uint256 absPrice = price >= 0 ? uint256(uint64(price)) : uint256(uint64(-price));
        require(absPrice > 0, "ParimutuelPythResolver: zero price");
        require(uint256(conf) * 10_000 <= absPrice * confThresholdBps, "ParimutuelPythResolver: confidence too wide");
    }
}
