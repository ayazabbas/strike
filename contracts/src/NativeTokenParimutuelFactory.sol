// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./NativeTokenPoolTypes.sol";

interface INativeTokenPoolManagerView {
    function marketTotalPrincipal(uint256 marketId) external view returns (uint256);
    function getOutcomePool(uint256 marketId, uint8 outcomeId) external view returns (ParimutuelOutcomePool memory);
}

/// @title NativeTokenParimutuelFactory
/// @notice Permissionless arbitrary-token market creation and v1 resolution/challenge lifecycle for Flap Token Pools.
contract NativeTokenParimutuelFactory is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    uint128 public constant INDEPENDENT_LOG_LIQUIDITY_MIN = 1_000e18;
    uint128 public constant INDEPENDENT_LOG_LIQUIDITY_MAX = 1_000_000e18;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint64 public constant CHALLENGE_WINDOW = 30 minutes;

    uint256 public nextMarketId = 1;
    bool public paused;
    address public poolManager;
    address public protocolTreasury;
    uint256 public creatorBondAmount = 0.05 ether;
    uint256 public challengerBondAmount = 0.01 ether;
    uint16 public platformFeeBps = 200;

    mapping(uint256 => NativeTokenPoolMarket) internal _markets;
    mapping(uint256 => NativeTokenPoolChallenge) internal _challenges;
    mapping(address => uint256) public pendingNativePayouts;

    event NativeTokenPoolMarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        address indexed collateralToken,
        uint8 outcomeCount,
        uint64 tradingCloseTime,
        uint64 resolutionTime,
        uint16 feeBps,
        uint256 minStake,
        uint256 maxStake,
        bytes32 metadataHash,
        string metadataURI
    );
    event NativeTokenPoolPromptConfigured(uint256 indexed marketId, string prompt);
    event NativeTokenPoolClosed(uint256 indexed marketId);
    event NativeTokenPoolResolved(uint256 indexed marketId, uint8 indexed winningOutcomeId);
    event NativeTokenPoolResolvedByResolver(
        uint256 indexed marketId, address indexed resolver, uint8 indexed winningOutcomeId
    );
    event NativeTokenPoolInvalidated(uint256 indexed marketId, NativeTokenPoolReason reason, bytes32 reasonHash);
    event NativeTokenPoolCancelled(uint256 indexed marketId, NativeTokenPoolReason reason, bytes32 reasonHash);
    event NativeTokenPoolChallengeOpened(
        uint256 indexed marketId,
        address indexed challenger,
        NativeTokenPoolReason reason,
        bytes32 reasonHash,
        uint256 bondAmount
    );
    event NativeTokenPoolChallengeResolved(
        uint256 indexed marketId,
        address indexed challenger,
        bool successful,
        NativeTokenPoolReason reason,
        bytes32 reasonHash
    );
    event NativeTokenPoolCreatorBondRefunded(uint256 indexed marketId, address indexed creator, uint256 amount);
    event NativeTokenPoolCreatorBondSlashed(
        uint256 indexed marketId,
        address indexed challenger,
        address indexed treasury,
        uint256 challengerAmount,
        uint256 treasuryAmount
    );
    event NativeTokenPoolChallengerBondRefunded(uint256 indexed marketId, address indexed challenger, uint256 amount);
    event NativeTokenPoolChallengerBondSlashed(
        uint256 indexed marketId,
        address indexed creator,
        address indexed treasury,
        uint256 creatorAmount,
        uint256 treasuryAmount
    );
    event NativeTokenPoolParamsUpdated(
        uint256 creatorBondAmount, uint256 challengerBondAmount, address indexed protocolTreasury
    );
    event NativeTokenPoolPlatformFeeUpdated(uint16 feeBps);
    event NativeTokenPoolFactoryPaused(bool paused);
    event NativeTokenPoolManagerUpdated(address indexed poolManager);
    event NativeTokenPoolNativePayoutWithdrawn(address indexed recipient, uint256 amount);

    constructor(address admin, address protocolTreasury_) {
        require(admin != address(0), "NativeTokenFactory: zero admin");
        require(protocolTreasury_ != address(0), "NativeTokenFactory: zero treasury");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        protocolTreasury = protocolTreasury_;
    }

    function createNativePoolMarket(NativeTokenPoolMarketConfig calldata config)
        external
        payable
        nonReentrant
        returns (uint256 marketId)
    {
        require(!paused, "NativeTokenFactory: paused");
        require(msg.value == creatorBondAmount, "NativeTokenFactory: creator bond required");
        require(config.collateralToken != address(0), "NativeTokenFactory: zero token");
        require(config.tradingCloseTime > block.timestamp, "NativeTokenFactory: trading close in past");
        require(config.resolutionTime >= config.tradingCloseTime, "NativeTokenFactory: resolution before trading close");
        require(config.outcomeCount >= 2 && config.outcomeCount <= 8, "NativeTokenFactory: invalid outcomeCount");
        require(config.feeBps == platformFeeBps, "NativeTokenFactory: invalid fee");
        require(config.minStake > 0, "NativeTokenFactory: zero min stake");
        require(config.maxStake == 0 || config.maxStake >= config.minStake, "NativeTokenFactory: invalid stake bounds");
        require(config.metadataHash != bytes32(0), "NativeTokenFactory: zero metadataHash");
        require(bytes(config.metadataURI).length > 0, "NativeTokenFactory: empty metadataURI");
        require(bytes(config.prompt).length > 0, "NativeTokenFactory: empty prompt");
        _validateCurveConfig(config.curveType, config.curveParam);

        marketId = nextMarketId++;
        _markets[marketId] = NativeTokenPoolMarket({
            marketId: marketId,
            creator: msg.sender,
            collateralToken: config.collateralToken,
            tradingCloseTime: config.tradingCloseTime,
            resolutionTime: config.resolutionTime,
            challengeDeadline: 0,
            outcomeCount: config.outcomeCount,
            state: ParimutuelMarketState.Open,
            curveType: config.curveType,
            curveParam: config.curveParam,
            feeBps: config.feeBps,
            minStake: config.minStake,
            maxStake: config.maxStake,
            winningOutcomeId: 0,
            hasWinner: false,
            finalized: false,
            creatorBondSettled: false,
            creatorBondAmount: msg.value,
            metadataHash: config.metadataHash,
            metadataURI: config.metadataURI,
            prompt: config.prompt
        });

        emit NativeTokenPoolMarketCreated(
            marketId,
            msg.sender,
            config.collateralToken,
            config.outcomeCount,
            config.tradingCloseTime,
            config.resolutionTime,
            config.feeBps,
            config.minStake,
            config.maxStake,
            config.metadataHash,
            config.metadataURI
        );
        emit NativeTokenPoolPromptConfigured(marketId, config.prompt);
    }

    function closeMarket(uint256 marketId) external {
        NativeTokenPoolMarket storage market = _requireMarket(marketId);
        require(market.state == ParimutuelMarketState.Open, "NativeTokenFactory: not open");
        require(block.timestamp >= market.tradingCloseTime, "NativeTokenFactory: trading still open");
        market.state = ParimutuelMarketState.Closed;
        emit NativeTokenPoolClosed(marketId);
    }

    function resolveToWinner(uint256 marketId, uint8 winningOutcomeId) external onlyRole(ADMIN_ROLE) {
        _resolveToWinner(marketId, winningOutcomeId, false);
    }

    function resolveFromFlapAI(uint256 marketId, uint8 winningOutcomeId) external onlyRole(RESOLVER_ROLE) {
        _resolveToWinner(marketId, winningOutcomeId, true);
    }

    function resolveInvalid(uint256 marketId, NativeTokenPoolReason reason, bytes32 reasonHash)
        external
        onlyRole(ADMIN_ROLE)
    {
        NativeTokenPoolMarket storage market = _requireMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Closed || market.state == ParimutuelMarketState.Resolving,
            "NativeTokenFactory: not invalidatable"
        );
        require(block.timestamp >= market.resolutionTime, "NativeTokenFactory: resolution too early");

        market.state = ParimutuelMarketState.Invalid;
        market.challengeDeadline = uint64(block.timestamp + CHALLENGE_WINDOW);
        emit NativeTokenPoolInvalidated(marketId, reason, reasonHash);
    }

    function cancelMarket(uint256 marketId, NativeTokenPoolReason reason, bytes32 reasonHash)
        external
        onlyRole(ADMIN_ROLE)
    {
        NativeTokenPoolMarket storage market = _requireMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Open || market.state == ParimutuelMarketState.Closed
                || market.state == ParimutuelMarketState.Resolving,
            "NativeTokenFactory: cannot cancel"
        );

        market.state = ParimutuelMarketState.Cancelled;
        market.challengeDeadline = uint64(block.timestamp + CHALLENGE_WINDOW);
        emit NativeTokenPoolCancelled(marketId, reason, reasonHash);
    }

    function openChallenge(uint256 marketId, NativeTokenPoolReason reason, bytes32 reasonHash)
        external
        payable
        nonReentrant
    {
        NativeTokenPoolMarket storage market = _requireMarket(marketId);
        require(_isTerminal(market.state), "NativeTokenFactory: market not challengeable");
        require(!market.finalized, "NativeTokenFactory: finalized");
        require(block.timestamp <= market.challengeDeadline, "NativeTokenFactory: challenge window closed");
        require(
            _challenges[marketId].status != NativeTokenPoolChallengeStatus.Open, "NativeTokenFactory: challenge open"
        );
        require(msg.value == challengerBondAmount, "NativeTokenFactory: challenger bond required");

        _challenges[marketId] = NativeTokenPoolChallenge({
            challenger: msg.sender,
            status: NativeTokenPoolChallengeStatus.Open,
            reason: reason,
            reasonHash: reasonHash,
            bondAmount: msg.value
        });
        emit NativeTokenPoolChallengeOpened(marketId, msg.sender, reason, reasonHash, msg.value);
    }

    function adjudicateChallenge(uint256 marketId, bool successful, NativeTokenPoolReason reason, bytes32 reasonHash)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        NativeTokenPoolMarket storage market = _requireMarket(marketId);
        NativeTokenPoolChallenge storage challenge = _challenges[marketId];
        require(challenge.status == NativeTokenPoolChallengeStatus.Open, "NativeTokenFactory: no open challenge");
        require(!market.finalized, "NativeTokenFactory: finalized");

        address challenger = challenge.challenger;
        uint256 challengerBond = challenge.bondAmount;
        challenge.reason = reason;
        challenge.reasonHash = reasonHash;

        if (successful) {
            challenge.status = NativeTokenPoolChallengeStatus.Successful;
            challenge.bondAmount = 0;
            _refundChallengerBond(marketId, challenger, challengerBond);
            _slashCreatorBond(marketId, challenger);
            market.state = ParimutuelMarketState.Invalid;
            market.hasWinner = false;
            market.finalized = true;
        } else {
            challenge.status = NativeTokenPoolChallengeStatus.Failed;
            challenge.bondAmount = 0;
            _slashChallengerBond(marketId, market.creator, challengerBond);
        }

        emit NativeTokenPoolChallengeResolved(marketId, challenger, successful, reason, reasonHash);
    }

    function finalizeMarket(uint256 marketId) external nonReentrant {
        NativeTokenPoolMarket storage market = _requireMarket(marketId);
        require(_isTerminal(market.state), "NativeTokenFactory: market not terminal");
        require(!market.finalized, "NativeTokenFactory: finalized");
        require(block.timestamp > market.challengeDeadline, "NativeTokenFactory: challenge window open");
        require(
            _challenges[marketId].status != NativeTokenPoolChallengeStatus.Open, "NativeTokenFactory: challenge open"
        );

        market.finalized = true;
        _refundCreatorBond(marketId);
    }

    function withdrawNativePayout() external nonReentrant returns (uint256 amount) {
        amount = pendingNativePayouts[msg.sender];
        require(amount > 0, "NativeTokenFactory: no native payout");
        pendingNativePayouts[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "NativeTokenFactory: native payout failed");
        emit NativeTokenPoolNativePayoutWithdrawn(msg.sender, amount);
    }

    function setPoolManager(address poolManager_) external onlyRole(ADMIN_ROLE) {
        require(poolManager == address(0), "NativeTokenFactory: manager already set");
        require(poolManager_ != address(0), "NativeTokenFactory: zero manager");
        poolManager = poolManager_;
        emit NativeTokenPoolManagerUpdated(poolManager_);
    }

    function setBondParams(uint256 creatorBondAmount_, uint256 challengerBondAmount_) external onlyRole(ADMIN_ROLE) {
        require(creatorBondAmount_ > 0, "NativeTokenFactory: zero creator bond");
        require(challengerBondAmount_ > 0, "NativeTokenFactory: zero challenger bond");
        creatorBondAmount = creatorBondAmount_;
        challengerBondAmount = challengerBondAmount_;
        emit NativeTokenPoolParamsUpdated(creatorBondAmount_, challengerBondAmount_, protocolTreasury);
    }

    function setPlatformFeeBps(uint16 platformFeeBps_) external onlyRole(ADMIN_ROLE) {
        require(platformFeeBps_ < BPS_DENOMINATOR, "NativeTokenFactory: invalid fee");
        platformFeeBps = platformFeeBps_;
        emit NativeTokenPoolPlatformFeeUpdated(platformFeeBps_);
    }

    function setProtocolTreasury(address protocolTreasury_) external onlyRole(ADMIN_ROLE) {
        require(protocolTreasury_ != address(0), "NativeTokenFactory: zero treasury");
        protocolTreasury = protocolTreasury_;
        emit NativeTokenPoolParamsUpdated(creatorBondAmount, challengerBondAmount, protocolTreasury_);
    }

    function pauseFactory(bool paused_) external onlyRole(ADMIN_ROLE) {
        paused = paused_;
        emit NativeTokenPoolFactoryPaused(paused_);
    }

    function getMarket(uint256 marketId) external view returns (NativeTokenPoolMarket memory) {
        return _requireMarket(marketId);
    }

    function getChallenge(uint256 marketId) external view returns (NativeTokenPoolChallenge memory) {
        return _challenges[marketId];
    }

    function getMarketState(uint256 marketId) external view returns (ParimutuelMarketState) {
        return _requireMarket(marketId).state;
    }

    function isFinalized(uint256 marketId) external view returns (bool) {
        return _requireMarket(marketId).finalized;
    }

    function _resolveToWinner(uint256 marketId, uint8 winningOutcomeId, bool byResolver) internal {
        NativeTokenPoolMarket storage market = _requireMarket(marketId);
        require(
            market.state == ParimutuelMarketState.Closed || market.state == ParimutuelMarketState.Resolving,
            "NativeTokenFactory: not resolvable"
        );
        require(block.timestamp >= market.resolutionTime, "NativeTokenFactory: resolution too early");
        require(winningOutcomeId < market.outcomeCount, "NativeTokenFactory: invalid winningOutcomeId");
        _requireResolvableWinningOutcome(marketId, winningOutcomeId);

        market.state = ParimutuelMarketState.Resolved;
        market.winningOutcomeId = winningOutcomeId;
        market.hasWinner = true;
        market.challengeDeadline = uint64(block.timestamp + CHALLENGE_WINDOW);

        emit NativeTokenPoolResolved(marketId, winningOutcomeId);
        if (byResolver) {
            emit NativeTokenPoolResolvedByResolver(marketId, msg.sender, winningOutcomeId);
        }
    }

    function _requireResolvableWinningOutcome(uint256 marketId, uint8 winningOutcomeId) internal view {
        if (poolManager == address(0)) {
            return;
        }
        INativeTokenPoolManagerView manager = INativeTokenPoolManagerView(poolManager);
        uint256 totalPrincipal = manager.marketTotalPrincipal(marketId);
        if (totalPrincipal == 0) {
            return;
        }
        ParimutuelOutcomePool memory winningPool = manager.getOutcomePool(marketId, winningOutcomeId);
        require(winningPool.rewardShares > 0, "NativeTokenFactory: empty winning outcome");
    }

    function _refundCreatorBond(uint256 marketId) internal {
        NativeTokenPoolMarket storage market = _markets[marketId];
        if (market.creatorBondSettled || market.creatorBondAmount == 0) {
            return;
        }
        market.creatorBondSettled = true;
        uint256 amount = market.creatorBondAmount;
        pendingNativePayouts[market.creator] += amount;
        emit NativeTokenPoolCreatorBondRefunded(marketId, market.creator, amount);
    }

    function _slashCreatorBond(uint256 marketId, address challenger) internal {
        NativeTokenPoolMarket storage market = _markets[marketId];
        require(!market.creatorBondSettled, "NativeTokenFactory: creator bond settled");
        market.creatorBondSettled = true;
        uint256 challengerAmount = market.creatorBondAmount / 2;
        uint256 treasuryAmount = market.creatorBondAmount - challengerAmount;
        pendingNativePayouts[challenger] += challengerAmount;
        pendingNativePayouts[protocolTreasury] += treasuryAmount;
        emit NativeTokenPoolCreatorBondSlashed(marketId, challenger, protocolTreasury, challengerAmount, treasuryAmount);
    }

    function _refundChallengerBond(uint256 marketId, address challenger, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        pendingNativePayouts[challenger] += amount;
        emit NativeTokenPoolChallengerBondRefunded(marketId, challenger, amount);
    }

    function _slashChallengerBond(uint256 marketId, address creator, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        uint256 creatorAmount = amount / 2;
        uint256 treasuryAmount = amount - creatorAmount;
        pendingNativePayouts[creator] += creatorAmount;
        pendingNativePayouts[protocolTreasury] += treasuryAmount;
        emit NativeTokenPoolChallengerBondSlashed(marketId, creator, protocolTreasury, creatorAmount, treasuryAmount);
    }

    function _validateCurveConfig(ParimutuelCurveType curveType, uint128 curveParam) internal pure {
        if (curveType == ParimutuelCurveType.Flat || curveType == ParimutuelCurveType.PiecewiseBand) {
            require(curveParam == 0, "NativeTokenFactory: invalid curve param");
            return;
        }
        if (curveType == ParimutuelCurveType.IndependentLog) {
            require(
                curveParam >= INDEPENDENT_LOG_LIQUIDITY_MIN && curveParam <= INDEPENDENT_LOG_LIQUIDITY_MAX,
                "NativeTokenFactory: invalid log liquidity"
            );
            return;
        }
        revert("NativeTokenFactory: invalid curve");
    }

    function _isTerminal(ParimutuelMarketState state) internal pure returns (bool) {
        return state == ParimutuelMarketState.Resolved || state == ParimutuelMarketState.Invalid
            || state == ParimutuelMarketState.Cancelled;
    }

    function _requireMarket(uint256 marketId) internal view returns (NativeTokenPoolMarket storage market) {
        market = _markets[marketId];
        require(market.creator != address(0), "NativeTokenFactory: market not found");
    }
}
