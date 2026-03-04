// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title OutcomeToken
/// @notice ERC-1155 multi-token for binary market outcomes.
///         Token IDs: marketId*2 = YES, marketId*2+1 = NO.
///         Minting and burning are access-controlled (MINTER_ROLE).
///         This contract does NOT handle collateral — that is the Vault's responsibility.
contract OutcomeToken is ERC1155, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event PairMinted(address indexed to, uint256 indexed marketId, uint256 amount);
    event PairBurned(address indexed from, uint256 indexed marketId, uint256 amount);
    event Redeemed(address indexed from, uint256 indexed marketId, uint256 amount, bool winningOutcome);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address admin) ERC1155("") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Token ID helpers
    // -------------------------------------------------------------------------

    /// @notice Returns the YES token ID for a market.
    function yesTokenId(uint256 marketId) public pure returns (uint256) {
        return marketId * 2;
    }

    /// @notice Returns the NO token ID for a market.
    function noTokenId(uint256 marketId) public pure returns (uint256) {
        return marketId * 2 + 1;
    }

    // -------------------------------------------------------------------------
    // Mint / Burn
    // -------------------------------------------------------------------------

    /// @dev Build the (ids, amounts) arrays for a YES+NO pair operation.
    function _pairArgs(uint256 marketId, uint256 amount)
        private
        pure
        returns (uint256[] memory ids, uint256[] memory amounts)
    {
        ids = new uint256[](2);
        amounts = new uint256[](2);
        ids[0] = yesTokenId(marketId);
        ids[1] = noTokenId(marketId);
        amounts[0] = amount;
        amounts[1] = amount;
    }

    /// @notice Mints one YES + one NO token per `amount` unit of collateral.
    /// @param to       Recipient of the tokens.
    /// @param marketId Market identifier.
    /// @param amount   Number of pairs to mint.
    function mintPair(address to, uint256 marketId, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(amount > 0, "OutcomeToken: zero amount");
        (uint256[] memory ids, uint256[] memory amounts) = _pairArgs(marketId, amount);
        _mintBatch(to, ids, amounts, "");
        emit PairMinted(to, marketId, amount);
    }

    /// @notice Mints a single outcome token (YES or NO) for gas-efficient settlement.
    /// @param to       Recipient of the token.
    /// @param marketId Market identifier.
    /// @param amount   Number of tokens to mint.
    /// @param isYes    True = mint YES token, false = mint NO token.
    function mintSingle(address to, uint256 marketId, uint256 amount, bool isYes) external onlyRole(MINTER_ROLE) {
        require(amount > 0, "OutcomeToken: zero amount");
        uint256 tokenId = isYes ? yesTokenId(marketId) : noTokenId(marketId);
        _mint(to, tokenId, amount, "");
    }

    /// @notice Burns one YES + one NO token per `amount`, returning collateral equivalence.
    /// @param from     Token holder to burn from.
    /// @param marketId Market identifier.
    /// @param amount   Number of pairs to burn.
    function burnPair(address from, uint256 marketId, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(amount > 0, "OutcomeToken: zero amount");
        (uint256[] memory ids, uint256[] memory amounts) = _pairArgs(marketId, amount);
        _burnBatch(from, ids, amounts);
        emit PairBurned(from, marketId, amount);
    }

    /// @notice Post-resolution: burn `amount` winning outcome tokens.
    ///         Caller (Vault/settlement contract) is responsible for releasing collateral.
    /// @param from           Token holder.
    /// @param marketId       Market identifier.
    /// @param amount         Number of winning tokens to burn.
    /// @param winningOutcome True = YES won, False = NO won.
    function redeem(address from, uint256 marketId, uint256 amount, bool winningOutcome)
        external
        onlyRole(MINTER_ROLE)
    {
        require(amount > 0, "OutcomeToken: zero amount");
        uint256 tokenId = winningOutcome ? yesTokenId(marketId) : noTokenId(marketId);
        _burn(from, tokenId, amount);
        emit Redeemed(from, marketId, amount, winningOutcome);
    }

    // -------------------------------------------------------------------------
    // ERC-165 override (required for AccessControl + ERC1155 multi-inheritance)
    // -------------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
