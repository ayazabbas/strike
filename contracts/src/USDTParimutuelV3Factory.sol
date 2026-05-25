// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./USDTParimutuelV3Types.sol";

/// @title USDTParimutuelV3Factory
/// @notice Isolated lifecycle surface for World Cup USDT parimutuel V3 markets.
contract USDTParimutuelV3Factory is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");

    uint256 public nextMarketId = 1;
    bool public paused;
    address public manager;

    mapping(uint256 => USDTParimutuelV3Market) internal _markets;

    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        uint8 outcomeCount,
        uint64 tradingCloseTime,
        uint64 resolutionTime,
        uint16 feeBps,
        uint256 indexed creditEventId,
        bool creditEnabled,
        bytes32 metadataHash,
        string metadataURI
    );
    event MarketClosed(uint256 indexed marketId);
    event MarketResolved(uint256 indexed marketId, uint8 indexed winningOutcomeId);
    event MarketInvalidated(uint256 indexed marketId);
    event MarketCancelled(uint256 indexed marketId);
    event FactoryPaused(bool paused);
    event ManagerUpdated(address indexed manager);

    error ZeroAddress();
    error Paused();
    error InvalidTime();
    error InvalidOutcomeCount();
    error InvalidOutcome();
    error InvalidFee();
    error ZeroMetadataHash();
    error MarketNotFound();
    error MarketNotOpen();
    error MarketNotResolvable();
    error ResolutionTooEarly();
    error ManagerAlreadySet();

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MARKET_CREATOR_ROLE, admin);
    }

    function createMarket(USDTParimutuelV3MarketConfig calldata config)
        external
        onlyRole(MARKET_CREATOR_ROLE)
        nonReentrant
        returns (uint256 marketId)
    {
        if (paused) revert Paused();
        if (config.tradingCloseTime <= block.timestamp || config.resolutionTime < config.tradingCloseTime) {
            revert InvalidTime();
        }
        if (config.outcomeCount < 2 || config.outcomeCount > 8) revert InvalidOutcomeCount();
        if (config.feeBps > 10_000) revert InvalidFee();
        if (config.metadataHash == bytes32(0)) revert ZeroMetadataHash();
        if (config.creditEnabled && config.creditEventId == 0) revert InvalidTime();

        marketId = nextMarketId++;
        _markets[marketId] = USDTParimutuelV3Market({
            marketId: marketId,
            creator: msg.sender,
            tradingCloseTime: config.tradingCloseTime,
            resolutionTime: config.resolutionTime,
            outcomeCount: config.outcomeCount,
            feeBps: config.feeBps,
            creditEventId: config.creditEventId,
            creditEnabled: config.creditEnabled,
            state: USDTParimutuelV3MarketState.Open,
            winningOutcomeId: 0,
            hasWinner: false,
            metadataHash: config.metadataHash,
            metadataURI: config.metadataURI
        });

        emit MarketCreated(
            marketId,
            msg.sender,
            config.outcomeCount,
            config.tradingCloseTime,
            config.resolutionTime,
            config.feeBps,
            config.creditEventId,
            config.creditEnabled,
            config.metadataHash,
            config.metadataURI
        );
    }

    function closeMarket(uint256 marketId) external {
        USDTParimutuelV3Market storage market = _requireMarket(marketId);
        if (market.state != USDTParimutuelV3MarketState.Open) revert MarketNotOpen();
        if (block.timestamp < market.tradingCloseTime) revert InvalidTime();

        market.state = USDTParimutuelV3MarketState.Closed;
        emit MarketClosed(marketId);
    }

    function resolveToWinner(uint256 marketId, uint8 winningOutcomeId) external onlyRole(ADMIN_ROLE) {
        USDTParimutuelV3Market storage market = _requireMarket(marketId);
        if (market.state != USDTParimutuelV3MarketState.Open && market.state != USDTParimutuelV3MarketState.Closed) {
            revert MarketNotResolvable();
        }
        if (block.timestamp < market.resolutionTime) revert ResolutionTooEarly();
        if (winningOutcomeId >= market.outcomeCount) revert InvalidOutcome();

        market.state = USDTParimutuelV3MarketState.Resolved;
        market.winningOutcomeId = winningOutcomeId;
        market.hasWinner = true;
        emit MarketResolved(marketId, winningOutcomeId);
    }

    function resolveInvalid(uint256 marketId) external onlyRole(ADMIN_ROLE) {
        USDTParimutuelV3Market storage market = _requireMarket(marketId);
        if (market.state != USDTParimutuelV3MarketState.Open && market.state != USDTParimutuelV3MarketState.Closed) {
            revert MarketNotResolvable();
        }
        if (block.timestamp < market.resolutionTime) revert ResolutionTooEarly();

        market.state = USDTParimutuelV3MarketState.Invalid;
        emit MarketInvalidated(marketId);
    }

    function cancelMarket(uint256 marketId) external onlyRole(ADMIN_ROLE) {
        USDTParimutuelV3Market storage market = _requireMarket(marketId);
        if (market.state == USDTParimutuelV3MarketState.Resolved) revert MarketNotResolvable();

        market.state = USDTParimutuelV3MarketState.Cancelled;
        emit MarketCancelled(marketId);
    }

    function pauseFactory(bool paused_) external onlyRole(ADMIN_ROLE) {
        paused = paused_;
        emit FactoryPaused(paused_);
    }

    function setManager(address manager_) external onlyRole(ADMIN_ROLE) {
        if (manager != address(0)) revert ManagerAlreadySet();
        if (manager_ == address(0)) revert ZeroAddress();

        manager = manager_;
        emit ManagerUpdated(manager_);
    }

    function getMarket(uint256 marketId) external view returns (USDTParimutuelV3Market memory) {
        return _requireMarket(marketId);
    }

    function _requireMarket(uint256 marketId) internal view returns (USDTParimutuelV3Market storage market) {
        market = _markets[marketId];
        if (market.marketId == 0) revert MarketNotFound();
    }
}
