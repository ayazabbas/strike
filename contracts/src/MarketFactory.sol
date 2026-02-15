// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Market} from "./Market.sol";

/// @title MarketFactory - Deploys prediction market clones using EIP-1167 minimal proxy
/// @notice Creates and manages Market instances with minimal gas cost
contract MarketFactory is Ownable {
    // ─── Events ──────────────────────────────────────────────────────────
    event MarketCreated(
        address indexed market,
        bytes32 indexed priceId,
        uint256 expiryTime,
        int64 strikePrice
    );
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event KeeperUpdated(address indexed oldKeeper, address indexed newKeeper);

    // ─── Storage ─────────────────────────────────────────────────────────
    address public immutable marketImplementation;
    address public immutable pyth;
    address public feeCollector;
    address public keeper;

    address[] public allMarkets;
    mapping(address => bool) public isMarket;

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyKeeper() {
        require(msg.sender == keeper || msg.sender == owner(), "Only keeper");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    constructor(address _pyth, address _feeCollector) Ownable(msg.sender) {
        require(_pyth != address(0), "Invalid Pyth address");
        require(_feeCollector != address(0), "Invalid fee collector");

        pyth = _pyth;
        feeCollector = _feeCollector;
        keeper = msg.sender; // Owner is default keeper

        // Deploy the implementation contract (used as clone template)
        marketImplementation = address(new Market());
    }

    // ─── Market Creation ─────────────────────────────────────────────────

    /// @notice Create a new prediction market. Only keeper can call.
    /// @param priceId Pyth price feed ID (e.g. BTC/USD)
    /// @param duration Market duration in seconds
    /// @param pythUpdateData Pyth price update data to capture strike price
    /// @return market Address of the new market
    function createMarket(
        bytes32 priceId,
        uint256 duration,
        bytes[] calldata pythUpdateData
    ) external payable onlyKeeper returns (address market) {
        require(duration >= 60, "Duration too short"); // Min 1 minute
        require(duration <= 7 days, "Duration too long");

        market = Clones.clone(marketImplementation);

        Market(payable(market)).initialize{value: msg.value}(
            pyth,
            priceId,
            duration,
            feeCollector,
            pythUpdateData
        );

        allMarkets.push(market);
        isMarket[market] = true;

        // Read strike price for the event
        int64 strikePrice = Market(payable(market)).strikePrice();
        uint256 expiryTime = Market(payable(market)).expiryTime();

        emit MarketCreated(market, priceId, expiryTime, strikePrice);
    }

    // ─── Keeper ──────────────────────────────────────────────────────────

    /// @notice Resolve a market. Only keeper can call.
    /// @param market Address of the market to resolve
    /// @param pythUpdateData Pyth price update data for resolution
    function resolveMarket(
        address market,
        bytes[] calldata pythUpdateData
    ) external payable onlyKeeper {
        require(isMarket[market], "Not a market");
        Market(payable(market)).resolve{value: msg.value}(pythUpdateData);
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    /// @notice Update the keeper address
    function setKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0), "Invalid address");
        address old = keeper;
        keeper = _keeper;
        emit KeeperUpdated(old, _keeper);
    }

    /// @notice Update the fee collector address
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Invalid address");
        address old = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(old, _feeCollector);
    }

    /// @notice Emergency pause a specific market
    function pauseMarket(address market) external onlyOwner {
        require(isMarket[market], "Not a market");
        Market(payable(market)).emergencyPause();
    }

    /// @notice Unpause a specific market
    function unpauseMarket(address market) external onlyOwner {
        require(isMarket[market], "Not a market");
        Market(payable(market)).emergencyUnpause();
    }

    /// @notice Emergency cancel a specific market
    function cancelMarket(address market) external onlyOwner {
        require(isMarket[market], "Not a market");
        Market(payable(market)).emergencyCancel();
    }

    // Allow factory to receive BNB refunds from Market.initialize and Market.resolve
    receive() external payable {}

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get total number of markets created
    function getMarketCount() external view returns (uint256) {
        return allMarkets.length;
    }

    /// @notice Get a page of market addresses
    /// @param offset Starting index
    /// @param limit Max number to return
    function getMarkets(uint256 offset, uint256 limit) external view returns (address[] memory markets) {
        uint256 len = allMarkets.length;
        if (offset >= len) return new address[](0);

        uint256 end = offset + limit;
        if (end > len) end = len;
        uint256 count = end - offset;

        markets = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            markets[i] = allMarkets[offset + i];
        }
    }
}
