// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./flap/IFlapAIProvider.sol";
import "./ParimutuelFactory.sol";
import "./ParimutuelTypes.sol";

/// @title ParimutuelAIResolver
/// @notice Flap AI resolver for multi-outcome parimutuel markets.
/// @dev The oracle returns an outcome index in `[0, outcomeCount)`. Challenges
///      follow the same liveness/bond shape as the binary AI resolver, with
///      admin override/fallback for contested or failed resolutions.
contract ParimutuelAIResolver is FlapAIConsumerBase {
    uint256 public constant LIVENESS_PERIOD = 30 minutes;
    uint256 public constant CHALLENGE_PERIOD = 24 hours;
    uint256 public constant CHALLENGE_BOND = 0.1 ether;
    uint256 public constant CHALLENGER_REWARD = 0.01 ether;
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    address public admin;
    address public treasury;
    ParimutuelFactory public immutable factory;
    uint256 public override lastRequestId;

    struct AIMarketConfig {
        string prompt;
        uint8 modelId;
        uint256 oracleFee;
        bool pending;
        bool resolved;
    }

    struct ProposedResolution {
        uint8 winningOutcomeId;
        uint256 livenessEnd;
        address challenger;
        uint256 challengeEnd;
        bool finalized;
    }

    mapping(uint256 => uint256) public requestToMarket;
    mapping(uint256 => AIMarketConfig) public aiMarkets;
    mapping(uint256 => ProposedResolution) public proposals;
    mapping(bytes32 => mapping(address => bool)) private _roles;

    address private _providerOverride;

    event ParimutuelAIConfigured(uint256 indexed marketId, uint8 modelId, uint256 oracleFee);
    event ParimutuelAIResolutionRequested(uint256 indexed marketId, uint256 requestId);
    event ParimutuelAIResolutionProposed(
        uint256 indexed marketId, uint256 requestId, uint8 winningOutcomeId, uint256 livenessEnd
    );
    event ParimutuelAIResolutionChallenged(uint256 indexed marketId, address challenger, uint256 challengeEnd);
    event ParimutuelAIResolutionConfirmed(uint256 indexed marketId, uint8 winningOutcomeId);
    event ParimutuelAIResolutionOverridden(
        uint256 indexed marketId, uint8 oldWinningOutcomeId, uint8 newWinningOutcomeId
    );
    event ParimutuelAIResolutionRefunded(uint256 indexed marketId, uint256 requestId);
    event ParimutuelAIResolutionInvalidChoice(uint256 indexed marketId, uint256 requestId, uint8 choice);
    event ParimutuelAIResolutionDefaulted(uint256 indexed marketId, uint8 winningOutcomeId, address challenger);

    error NotAdmin();
    error NotAuthorized();
    error MarketNotConfigured();
    error MarketAlreadyPending();
    error MarketAlreadyResolved();
    error WrongResolverType();
    error NoProposal();
    error LivenessNotExpired();
    error LivenessExpired();
    error AlreadyChallenged();
    error WrongBondAmount();
    error NotChallenged();
    error AlreadyFinalized();
    error ChallengeActive();
    error ChallengeNotExpired();
    error InvalidOutcome();
    error TransferFailed();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!_roles[role][msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(address _factory, address _treasury) {
        require(_factory != address(0), "ParimutuelAIResolver: zero factory");
        require(_treasury != address(0), "ParimutuelAIResolver: zero treasury");
        factory = ParimutuelFactory(_factory);
        treasury = _treasury;
        admin = msg.sender;
    }

    function grantRole(bytes32 role, address account) external onlyAdmin {
        _roles[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        _roles[role][account] = false;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }

    function setAdmin(address _admin) external onlyAdmin {
        require(_admin != address(0), "ParimutuelAIResolver: zero admin");
        admin = _admin;
    }

    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "ParimutuelAIResolver: zero treasury");
        treasury = _treasury;
    }

    function setProviderOverride(address provider) external onlyAdmin {
        _providerOverride = provider;
    }

    function _getFlapAIProvider() internal view override returns (address) {
        if (_providerOverride != address(0)) return _providerOverride;
        return super._getFlapAIProvider();
    }

    function configureMarket(uint256 marketId, string calldata prompt, uint8 modelId) external payable onlyAdmin {
        ParimutuelMarket memory market = factory.getMarket(marketId);
        if (market.resolverType != ParimutuelResolverType.AI) revert WrongResolverType();
        require(bytes(prompt).length > 0, "ParimutuelAIResolver: empty prompt");

        IFlapAIProvider provider = IFlapAIProvider(_getFlapAIProvider());
        uint256 requiredFee = provider.getModel(modelId).price;
        require(msg.value >= requiredFee, "ParimutuelAIResolver: insufficient fee");

        AIMarketConfig storage config = aiMarkets[marketId];
        require(!config.pending, "ParimutuelAIResolver: pending");
        require(!config.resolved, "ParimutuelAIResolver: resolved");
        config.prompt = prompt;
        config.modelId = modelId;
        config.oracleFee += requiredFee;

        uint256 excess = msg.value - requiredFee;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            if (!ok) revert TransferFailed();
        }

        emit ParimutuelAIConfigured(marketId, modelId, requiredFee);
    }

    function resolveMarket(uint256 marketId) external onlyRole(KEEPER_ROLE) {
        AIMarketConfig storage config = aiMarkets[marketId];
        if (bytes(config.prompt).length == 0) revert MarketNotConfigured();
        if (config.pending) revert MarketAlreadyPending();
        if (config.resolved) revert MarketAlreadyResolved();

        ParimutuelMarket memory market = factory.getMarket(marketId);
        if (factory.currentResolverType(marketId) != ParimutuelResolverType.AI) revert WrongResolverType();

        if (market.state == ParimutuelMarketState.Open && block.timestamp >= market.closeTime) {
            factory.closeMarket(marketId);
            market.state = ParimutuelMarketState.Closed;
        }
        require(
            market.state == ParimutuelMarketState.Closed || market.state == ParimutuelMarketState.Resolving,
            "ParimutuelAIResolver: market not closed"
        );
        if (market.state == ParimutuelMarketState.Closed) {
            factory.requestResolution(marketId);
        }

        IFlapAIProvider provider = IFlapAIProvider(_getFlapAIProvider());
        uint256 fee = provider.getModel(config.modelId).price;
        require(address(this).balance >= fee, "ParimutuelAIResolver: insufficient BNB");
        config.pending = true;

        uint256 requestId = provider.reason{value: fee}(config.modelId, config.prompt, market.outcomeCount);
        requestToMarket[requestId] = marketId;
        lastRequestId = requestId;

        emit ParimutuelAIResolutionRequested(marketId, requestId);
    }

    function _fulfillReasoning(uint256 requestId, uint8 choice) internal override {
        uint256 marketId = requestToMarket[requestId];
        AIMarketConfig storage config = aiMarkets[marketId];
        config.pending = false;

        ParimutuelMarket memory market = factory.getMarket(marketId);
        if (choice >= market.outcomeCount) {
            emit ParimutuelAIResolutionInvalidChoice(marketId, requestId, choice);
            return;
        }

        uint256 livenessEnd = block.timestamp + LIVENESS_PERIOD;
        proposals[marketId] = ProposedResolution({
            winningOutcomeId: choice,
            livenessEnd: livenessEnd,
            challenger: address(0),
            challengeEnd: 0,
            finalized: false
        });

        emit ParimutuelAIResolutionProposed(marketId, requestId, choice, livenessEnd);
    }

    function _onFlapAIRequestRefunded(uint256 requestId) internal override {
        uint256 marketId = requestToMarket[requestId];
        aiMarkets[marketId].pending = false;
        emit ParimutuelAIResolutionRefunded(marketId, requestId);
    }

    function challenge(uint256 marketId) external payable {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (block.timestamp >= proposal.livenessEnd) revert LivenessExpired();
        if (proposal.challenger != address(0)) revert AlreadyChallenged();
        if (msg.value != CHALLENGE_BOND) revert WrongBondAmount();

        proposal.challenger = msg.sender;
        proposal.challengeEnd = block.timestamp + CHALLENGE_PERIOD;
        emit ParimutuelAIResolutionChallenged(marketId, msg.sender, proposal.challengeEnd);
    }

    function finalise(uint256 marketId) external {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (block.timestamp < proposal.livenessEnd) revert LivenessNotExpired();
        if (proposal.challenger != address(0)) revert ChallengeActive();

        _finalise(marketId, proposal.winningOutcomeId);
        emit ParimutuelAIResolutionConfirmed(marketId, proposal.winningOutcomeId);
    }

    function confirmResolution(uint256 marketId) external onlyAdmin {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (proposal.challenger == address(0)) revert NotChallenged();

        (bool ok,) = treasury.call{value: CHALLENGE_BOND}("");
        if (!ok) revert TransferFailed();

        _finalise(marketId, proposal.winningOutcomeId);
        emit ParimutuelAIResolutionConfirmed(marketId, proposal.winningOutcomeId);
    }

    function overrideResolution(uint256 marketId, uint8 newWinningOutcomeId) external onlyAdmin {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (proposal.challenger == address(0)) revert NotChallenged();
        ParimutuelMarket memory market = factory.getMarket(marketId);
        if (newWinningOutcomeId >= market.outcomeCount) revert InvalidOutcome();

        uint8 oldChoice = proposal.winningOutcomeId;
        uint256 payout = CHALLENGE_BOND + CHALLENGER_REWARD;
        (bool ok,) = proposal.challenger.call{value: payout}("");
        if (!ok) revert TransferFailed();

        _finalise(marketId, newWinningOutcomeId);
        emit ParimutuelAIResolutionOverridden(marketId, oldChoice, newWinningOutcomeId);
    }

    function finaliseAfterChallengeTimeout(uint256 marketId) external {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (proposal.challenger == address(0)) revert NotChallenged();
        if (block.timestamp < proposal.challengeEnd) revert ChallengeNotExpired();

        (bool ok,) = treasury.call{value: CHALLENGE_BOND}("");
        if (!ok) revert TransferFailed();

        _finalise(marketId, proposal.winningOutcomeId);
        emit ParimutuelAIResolutionDefaulted(marketId, proposal.winningOutcomeId, proposal.challenger);
    }

    function _finalise(uint256 marketId, uint8 winningOutcomeId) internal {
        ProposedResolution storage proposal = proposals[marketId];
        proposal.finalized = true;
        aiMarkets[marketId].resolved = true;
        factory.resolveFromResolver(marketId, winningOutcomeId);
    }

    function withdraw() external onlyAdmin {
        (bool ok,) = admin.call{value: address(this).balance}("");
        if (!ok) revert TransferFailed();
    }

    receive() external payable {}
}
