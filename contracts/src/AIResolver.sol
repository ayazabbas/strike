// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./flap/IFlapAIProvider.sol";
import "./MarketFactory.sol";

contract AIResolver is FlapAIConsumerBase {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant LIVENESS_PERIOD = 5 minutes;
    uint256 public constant CHALLENGE_PERIOD = 24 hours;
    uint256 public constant CHALLENGE_BOND = 0.1 ether;
    uint256 public constant CHALLENGER_REWARD = 0.01 ether;
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    address public admin;
    address public treasury;
    MarketFactory public immutable factory;
    uint256 public override lastRequestId;

    struct AIMarketConfig {
        string prompt;
        uint8 modelId;
        uint256 oracleFee;  // BNB locked at creation
        bool pending;       // true while awaiting oracle callback
        bool resolved;
    }

    struct ProposedResolution {
        uint8 choice;           // 0 = YES, 1 = NO
        uint256 livenessEnd;
        address challenger;
        uint256 challengeEnd;
        bool finalized;
    }

    mapping(uint256 => uint256) public requestToMarket;
    mapping(uint256 => AIMarketConfig) public aiMarkets;
    mapping(uint256 => ProposedResolution) public proposals;
    mapping(bytes32 => mapping(address => bool)) private _roles;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event AIResolutionRequested(uint256 indexed marketId, uint256 requestId);
    event AIResolutionProposed(uint256 indexed marketId, uint256 requestId, uint8 choice, uint256 livenessEnd);
    event AIResolutionChallenged(uint256 indexed marketId, address challenger, uint256 challengeEnd);
    event AIResolutionConfirmed(uint256 indexed marketId, uint8 choice);
    event AIResolutionOverridden(uint256 indexed marketId, uint8 oldChoice, bool newOutcome);
    event AIResolutionRefunded(uint256 indexed marketId, uint256 requestId);
    event AIResolutionDefaulted(uint256 indexed marketId, uint8 choice, address challenger);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotAdmin();
    error NotAuthorized();
    error MarketNotConfigured();
    error MarketAlreadyPending();
    error MarketAlreadyResolved();
    error NoProposal();
    error LivenessNotExpired();
    error LivenessExpired();
    error AlreadyChallenged();
    error WrongBondAmount();
    error NotChallenged();
    error AlreadyFinalized();
    error ChallengeActive();
    error ChallengeNotExpired();
    error TransferFailed();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!_roles[role][msg.sender]) revert NotAuthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _factory, address _treasury) {
        require(_factory != address(0), "AIResolver: zero factory");
        require(_treasury != address(0), "AIResolver: zero treasury");
        factory = MarketFactory(_factory);
        treasury = _treasury;
        admin = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function grantRole(bytes32 role, address account) external onlyAdmin {
        _roles[role][account] = true;
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        _roles[role][account] = false;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }

    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "AIResolver: zero treasury");
        treasury = _treasury;
    }

    function setAdmin(address _admin) external onlyAdmin {
        require(_admin != address(0), "AIResolver: zero admin");
        admin = _admin;
    }

    // -------------------------------------------------------------------------
    // Provider override (for testing / custom deployments)
    // -------------------------------------------------------------------------

    address private _providerOverride;

    function setProviderOverride(address provider) external onlyAdmin {
        _providerOverride = provider;
    }

    function _getFlapAIProvider() internal view virtual override returns (address) {
        if (_providerOverride != address(0)) return _providerOverride;
        return super._getFlapAIProvider();
    }

    // -------------------------------------------------------------------------
    // Fee deposit (called by MarketFactory)
    // -------------------------------------------------------------------------

    function depositFee(uint256 marketId, string calldata prompt, uint8 modelId) external payable {
        require(msg.value > 0, "AIResolver: zero fee");
        AIMarketConfig storage config = aiMarkets[marketId];
        config.prompt = prompt;
        config.modelId = modelId;
        config.oracleFee = msg.value;
    }

    // -------------------------------------------------------------------------
    // Resolution flow
    // -------------------------------------------------------------------------

    function resolveMarket(uint256 marketId) external onlyRole(KEEPER_ROLE) {
        AIMarketConfig storage config = aiMarkets[marketId];
        if (bytes(config.prompt).length == 0) revert MarketNotConfigured();
        if (config.pending) revert MarketAlreadyPending();
        if (config.resolved) revert MarketAlreadyResolved();

        // Close market if still open and expired
        (, , uint256 expiryTime, , MarketState state, , , , , ) = factory.marketMeta(marketId);
        if (state == MarketState.Open && block.timestamp >= expiryTime) {
            factory.closeMarket(marketId);
            state = MarketState.Closed;
        }

        require(
            state == MarketState.Closed || state == MarketState.Resolving,
            "AIResolver: market not closed"
        );

        // Set resolving state (skip if already resolving from prior attempt)
        if (state == MarketState.Closed) {
            factory.setResolving(marketId);
        }

        // Query live oracle fee
        IFlapAIProvider provider = IFlapAIProvider(_getFlapAIProvider());
        uint256 fee = provider.getModel(config.modelId).price;
        require(address(this).balance >= fee, "AIResolver: insufficient BNB");

        config.pending = true;

        uint256 requestId = provider.reason{value: fee}(config.modelId, config.prompt, 2);
        requestToMarket[requestId] = marketId;
        lastRequestId = requestId;

        emit AIResolutionRequested(marketId, requestId);
    }

    function _fulfillReasoning(uint256 requestId, uint8 choice) internal override {
        uint256 marketId = requestToMarket[requestId];
        AIMarketConfig storage config = aiMarkets[marketId];
        config.pending = false;

        uint256 livenessEnd = block.timestamp + LIVENESS_PERIOD;
        proposals[marketId] = ProposedResolution({
            choice: choice,
            livenessEnd: livenessEnd,
            challenger: address(0),
            challengeEnd: 0,
            finalized: false
        });

        emit AIResolutionProposed(marketId, requestId, choice, livenessEnd);
    }

    function _onFlapAIRequestRefunded(uint256 requestId) internal override {
        uint256 marketId = requestToMarket[requestId];
        AIMarketConfig storage config = aiMarkets[marketId];
        config.pending = false;

        emit AIResolutionRefunded(marketId, requestId);
    }

    // -------------------------------------------------------------------------
    // Challenge
    // -------------------------------------------------------------------------

    function challenge(uint256 marketId) external payable {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (block.timestamp >= proposal.livenessEnd) revert LivenessExpired();
        if (proposal.challenger != address(0)) revert AlreadyChallenged();
        if (msg.value != CHALLENGE_BOND) revert WrongBondAmount();

        proposal.challenger = msg.sender;
        proposal.challengeEnd = block.timestamp + CHALLENGE_PERIOD;

        emit AIResolutionChallenged(marketId, msg.sender, proposal.challengeEnd);
    }

    // -------------------------------------------------------------------------
    // Finalise (no challenge path)
    // -------------------------------------------------------------------------

    function finalise(uint256 marketId) external {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (block.timestamp < proposal.livenessEnd) revert LivenessNotExpired();
        if (proposal.challenger != address(0)) revert ChallengeActive();

        proposal.finalized = true;
        aiMarkets[marketId].resolved = true;

        bool outcomeYes = proposal.choice == 0;
        factory.setResolved(marketId, outcomeYes, 0);

        emit AIResolutionConfirmed(marketId, proposal.choice);
    }

    // -------------------------------------------------------------------------
    // Admin resolution (challenge path)
    // -------------------------------------------------------------------------

    function confirmResolution(uint256 marketId) external onlyAdmin {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (proposal.challenger == address(0)) revert NotChallenged();

        proposal.finalized = true;
        aiMarkets[marketId].resolved = true;

        // Challenger loses bond to treasury
        (bool ok, ) = treasury.call{value: CHALLENGE_BOND}("");
        if (!ok) revert TransferFailed();

        bool outcomeYes = proposal.choice == 0;
        factory.setResolved(marketId, outcomeYes, 0);

        emit AIResolutionConfirmed(marketId, proposal.choice);
    }

    function overrideResolution(uint256 marketId, bool newOutcome) external onlyAdmin {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (proposal.challenger == address(0)) revert NotChallenged();

        uint8 oldChoice = proposal.choice;
        proposal.finalized = true;
        aiMarkets[marketId].resolved = true;

        // Return bond + reward to challenger
        uint256 payout = CHALLENGE_BOND + CHALLENGER_REWARD;
        (bool ok, ) = proposal.challenger.call{value: payout}("");
        if (!ok) revert TransferFailed();

        factory.setResolved(marketId, newOutcome, 0);

        emit AIResolutionOverridden(marketId, oldChoice, newOutcome);
    }

    // -------------------------------------------------------------------------
    // Challenge timeout (anyone can call after 24h if admin didn't act)
    // -------------------------------------------------------------------------

    /// @notice Finalise resolution after challenge period expires without admin action.
    ///         AI's original answer is accepted, challenger loses bond to treasury.
    ///         Anyone can call this — ensures markets don't stay stuck indefinitely.
    function finaliseAfterChallengeTimeout(uint256 marketId) external {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (proposal.challenger == address(0)) revert NotChallenged();
        if (block.timestamp < proposal.challengeEnd) revert ChallengeNotExpired();

        proposal.finalized = true;
        aiMarkets[marketId].resolved = true;

        // Challenger loses bond to treasury (same as confirmResolution)
        (bool ok, ) = treasury.call{value: CHALLENGE_BOND}("");
        if (!ok) revert TransferFailed();

        bool outcomeYes = proposal.choice == 0;
        factory.setResolved(marketId, outcomeYes, 0);

        emit AIResolutionDefaulted(marketId, proposal.choice, proposal.challenger);
    }

    // -------------------------------------------------------------------------
    // Emergency
    // -------------------------------------------------------------------------

    function withdraw() external onlyAdmin {
        (bool ok, ) = admin.call{value: address(this).balance}("");
        if (!ok) revert TransferFailed();
    }

    receive() external payable {}
}
