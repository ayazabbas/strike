// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ITypes.sol";
import "./MarketFactory.sol";
import "./OutcomeToken.sol";
import "./Vault.sol";

/// @title Redemption
/// @notice Handles post-resolution token redemption for binary outcome markets.
///         Users burn winning outcome tokens 1:1 for collateral (USDT).
contract Redemption is ReentrancyGuard {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    MarketFactory public immutable factory;
    OutcomeToken public immutable outcomeToken;
    Vault public immutable vault;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Redeemed(
        uint256 indexed factoryMarketId,
        address indexed user,
        uint256 amount,
        bool outcomeYes
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _factory, address _outcomeToken, address _vault) {
        require(_factory != address(0), "Redemption: zero factory");
        require(_outcomeToken != address(0), "Redemption: zero outcomeToken");
        require(_vault != address(0), "Redemption: zero vault");

        factory = MarketFactory(_factory);
        outcomeToken = OutcomeToken(_outcomeToken);
        vault = Vault(_vault);
    }

    // -------------------------------------------------------------------------
    // Redeem
    // -------------------------------------------------------------------------

    /// @notice Redeem winning outcome tokens for collateral.
    ///         Burns `amount` of the winning token and sends USDT to msg.sender.
    /// @param factoryMarketId The factory market ID.
    /// @param amount Number of winning outcome tokens to redeem.
    function redeem(uint256 factoryMarketId, uint256 amount) external nonReentrant {
        require(amount > 0, "Redemption: zero amount");

        (
            ,
            ,
            ,
            ,
            MarketState state,
            bool outcomeYes,
            ,
            uint256 orderBookMarketId
        ) = factory.marketMeta(factoryMarketId);

        require(state == MarketState.Resolved, "Redemption: not resolved");

        // Burn winning outcome tokens
        outcomeToken.redeem(msg.sender, orderBookMarketId, amount, outcomeYes);

        // Each outcome token represents 1 lot = LOT_SIZE worth of collateral
        uint256 payout = amount * LOT_SIZE;

        // Pay out from the market's redemption pool
        vault.redeemFromPool(orderBookMarketId, msg.sender, payout);

        emit Redeemed(factoryMarketId, msg.sender, amount, outcomeYes);
    }
}
