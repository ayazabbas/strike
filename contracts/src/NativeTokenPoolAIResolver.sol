// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./NativeTokenParimutuelFactory.sol";
import "./NativeTokenPoolTypes.sol";
import "./flap/IFlapAIProvider.sol";

/// @title NativeTokenPoolAIResolver
/// @notice Flap AI resolver for native Flap Token Pool markets.
/// @dev Uses the market prompt and outcome count stored by the native pool factory.
contract NativeTokenPoolAIResolver is FlapAIConsumerBase {
    uint256 public constant LIVENESS_PERIOD = 30 minutes;
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    address public admin;
    NativeTokenParimutuelFactory public immutable factory;
    uint256 public override lastRequestId;
    uint256 public defaultModelId;

    struct PendingRequest {
        uint256 requestId;
        uint256 modelId;
        bool pending;
        bool resolved;
    }

    struct ProposedResolution {
        uint8 winningOutcomeId;
        uint256 livenessEnd;
        bool finalized;
    }

    mapping(uint256 => uint256) public requestToMarket;
    mapping(uint256 => PendingRequest) public requests;
    mapping(uint256 => ProposedResolution) public proposals;
    mapping(bytes32 => mapping(address => bool)) private _roles;

    address private _providerOverride;

    event NativeTokenPoolAIModelUpdated(uint256 modelId);
    event NativeTokenPoolAIResolutionRequested(uint256 indexed marketId, uint256 indexed requestId);
    event NativeTokenPoolAIResolutionProposed(
        uint256 indexed marketId, uint256 indexed requestId, uint8 winningOutcomeId, uint256 livenessEnd
    );
    event NativeTokenPoolAIResolutionConfirmed(
        uint256 indexed marketId, uint256 indexed requestId, uint8 winningOutcomeId
    );
    event NativeTokenPoolAIResolutionRefunded(uint256 indexed marketId, uint256 indexed requestId);
    event NativeTokenPoolAIResolutionInvalidChoice(uint256 indexed marketId, uint256 indexed requestId, uint8 choice);

    error NotAdmin();
    error NotAuthorized();
    error MarketAlreadyPending();
    error MarketAlreadyResolved();
    error MarketNotClosed();
    error ResolutionTooEarly();
    error NoProposal();
    error UnknownRequest();
    error RequestNotPending();
    error LivenessNotExpired();
    error AlreadyFinalized();
    error TransferFailed();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!_roles[role][msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(address _factory, uint256 _defaultModelId) {
        require(_factory != address(0), "NativeTokenPoolAIResolver: zero factory");
        factory = NativeTokenParimutuelFactory(_factory);
        admin = msg.sender;
        defaultModelId = _defaultModelId;
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
        require(_admin != address(0), "NativeTokenPoolAIResolver: zero admin");
        admin = _admin;
    }

    function setDefaultModelId(uint256 modelId) external onlyAdmin {
        defaultModelId = modelId;
        emit NativeTokenPoolAIModelUpdated(modelId);
    }

    function setProviderOverride(address provider) external onlyAdmin {
        _providerOverride = provider;
    }

    function _getFlapAIProvider() internal view override returns (address) {
        if (_providerOverride != address(0)) return _providerOverride;
        return super._getFlapAIProvider();
    }

    function resolveMarket(uint256 marketId) external onlyRole(KEEPER_ROLE) {
        PendingRequest storage pending = requests[marketId];
        if (pending.pending) revert MarketAlreadyPending();
        if (pending.resolved) revert MarketAlreadyResolved();

        NativeTokenPoolMarket memory market = factory.getMarket(marketId);
        if (market.state == ParimutuelMarketState.Open && block.timestamp >= market.tradingCloseTime) {
            factory.closeMarket(marketId);
            market.state = ParimutuelMarketState.Closed;
        }
        if (market.state != ParimutuelMarketState.Closed && market.state != ParimutuelMarketState.Resolving) {
            revert MarketNotClosed();
        }
        if (block.timestamp < market.resolutionTime) revert ResolutionTooEarly();

        IFlapAIProvider provider = IFlapAIProvider(_getFlapAIProvider());
        uint256 fee = provider.getModel(defaultModelId).price;
        require(address(this).balance >= fee, "NativeTokenPoolAIResolver: insufficient BNB");

        pending.pending = true;
        pending.modelId = defaultModelId;

        uint256 requestId = provider.reason{value: fee}(defaultModelId, market.prompt, market.outcomeCount);
        pending.requestId = requestId;
        requestToMarket[requestId] = marketId;
        lastRequestId = requestId;

        emit NativeTokenPoolAIResolutionRequested(marketId, requestId);
    }

    function _fulfillReasoning(uint256 requestId, uint8 choice) internal override {
        uint256 marketId = requestToMarket[requestId];
        PendingRequest storage pending = requests[marketId];
        if (marketId == 0 || pending.requestId != requestId) revert UnknownRequest();
        if (!pending.pending) revert RequestNotPending();
        pending.pending = false;

        NativeTokenPoolMarket memory market = factory.getMarket(marketId);
        if (choice >= market.outcomeCount) {
            emit NativeTokenPoolAIResolutionInvalidChoice(marketId, requestId, choice);
            return;
        }

        uint256 livenessEnd = block.timestamp + LIVENESS_PERIOD;
        proposals[marketId] = ProposedResolution({winningOutcomeId: choice, livenessEnd: livenessEnd, finalized: false});

        emit NativeTokenPoolAIResolutionProposed(marketId, requestId, choice, livenessEnd);
    }

    function _onFlapAIRequestRefunded(uint256 requestId) internal override {
        uint256 marketId = requestToMarket[requestId];
        PendingRequest storage pending = requests[marketId];
        if (marketId == 0 || pending.requestId != requestId) revert UnknownRequest();
        if (!pending.pending) revert RequestNotPending();
        pending.pending = false;
        emit NativeTokenPoolAIResolutionRefunded(marketId, requestId);
    }

    function finalise(uint256 marketId) external {
        ProposedResolution storage proposal = proposals[marketId];
        if (proposal.livenessEnd == 0) revert NoProposal();
        if (proposal.finalized) revert AlreadyFinalized();
        if (block.timestamp < proposal.livenessEnd) revert LivenessNotExpired();

        proposal.finalized = true;
        requests[marketId].resolved = true;
        factory.resolveFromFlapAI(marketId, proposal.winningOutcomeId);

        emit NativeTokenPoolAIResolutionConfirmed(marketId, requests[marketId].requestId, proposal.winningOutcomeId);
    }

    function withdraw() external onlyAdmin {
        (bool ok,) = admin.call{value: address(this).balance}("");
        if (!ok) revert TransferFailed();
    }

    receive() external payable {}
}
