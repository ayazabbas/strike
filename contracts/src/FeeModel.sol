// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title FeeModel
/// @notice Pure fee-calculation contract for the Strike CLOB protocol.
///         All values are immutable from the protocol's perspective per trade;
///         the admin can update parameters for future trades.
///
///         Fee schedule
///         ------------
///         takerFeeBps       — taker fee in basis points (e.g. 30 = 0.30%)
///         makerRebateBps    — maker rebate in basis points (e.g. 10 = 0.10%)
///                             Must be <= takerFeeBps (rebate funded from taker fees)
///         resolverBounty    — fixed BNB amount per market resolution
///         prunerBounty      — fixed BNB amount per pruned order
///         protocolFeeCollector — address that receives protocol's net fee share
///
///         All transfer logic is handled by the caller (Vault / settlement contracts).
///         This contract only performs pure calculations.
contract FeeModel is AccessControl {
    uint256 public constant MAX_BPS = 10_000;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    uint256 public takerFeeBps;
    uint256 public makerRebateBps;
    uint256 public resolverBounty;
    uint256 public prunerBounty;
    address public protocolFeeCollector;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event FeeParamsUpdated(uint256 takerFeeBps, uint256 makerRebateBps);
    event BountiesUpdated(uint256 resolverBounty, uint256 prunerBounty);
    event ProtocolFeeCollectorUpdated(address indexed collector);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param admin               Admin address (can update params).
    /// @param _takerFeeBps        Initial taker fee in BPS.
    /// @param _makerRebateBps     Initial maker rebate in BPS (must be <= takerFeeBps).
    /// @param _resolverBounty     Initial resolver bounty in wei.
    /// @param _prunerBounty       Initial pruner bounty in wei.
    /// @param _protocolFeeCollector Initial fee collector address.
    constructor(
        address admin,
        uint256 _takerFeeBps,
        uint256 _makerRebateBps,
        uint256 _resolverBounty,
        uint256 _prunerBounty,
        address _protocolFeeCollector
    ) {
        require(_takerFeeBps <= MAX_BPS, "FeeModel: takerFee > 100%");
        require(_makerRebateBps <= _takerFeeBps, "FeeModel: rebate > takerFee");
        require(_protocolFeeCollector != address(0), "FeeModel: zero collector");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        takerFeeBps = _takerFeeBps;
        makerRebateBps = _makerRebateBps;
        resolverBounty = _resolverBounty;
        prunerBounty = _prunerBounty;
        protocolFeeCollector = _protocolFeeCollector;
    }

    // -------------------------------------------------------------------------
    // Pure calculations
    // -------------------------------------------------------------------------

    /// @notice Returns the taker fee for a given trade amount.
    /// @param amount Trade amount in wei.
    /// @return fee Taker fee in wei.
    function calculateTakerFee(uint256 amount) public view returns (uint256 fee) {
        fee = (amount * takerFeeBps) / MAX_BPS;
    }

    /// @notice Returns the maker rebate for a given trade amount.
    /// @param amount Trade amount in wei.
    /// @return rebate Maker rebate in wei.
    function calculateMakerRebate(uint256 amount) public view returns (uint256 rebate) {
        rebate = (amount * makerRebateBps) / MAX_BPS;
    }

    /// @notice Returns the net protocol fee (taker fee minus maker rebate) for a trade.
    ///         This is the amount that flows to `protocolFeeCollector`.
    /// @param amount Trade amount in wei.
    /// @return netFee Protocol's share in wei.
    function calculateNetProtocolFee(uint256 amount) public view returns (uint256 netFee) {
        netFee = calculateTakerFee(amount) - calculateMakerRebate(amount);
    }

    // -------------------------------------------------------------------------
    // Admin parameter updates
    // -------------------------------------------------------------------------

    /// @notice Update maker/taker fee schedule.
    /// @param _takerFeeBps    New taker fee in BPS.
    /// @param _makerRebateBps New maker rebate in BPS (must be <= takerFeeBps).
    function setFeeParams(uint256 _takerFeeBps, uint256 _makerRebateBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_takerFeeBps <= MAX_BPS, "FeeModel: takerFee > 100%");
        require(_makerRebateBps <= _takerFeeBps, "FeeModel: rebate > takerFee");
        takerFeeBps = _takerFeeBps;
        makerRebateBps = _makerRebateBps;
        emit FeeParamsUpdated(_takerFeeBps, _makerRebateBps);
    }

    /// @notice Update resolver and pruner bounties.
    /// @param _resolverBounty New resolver bounty in wei.
    /// @param _prunerBounty   New pruner bounty in wei.
    function setBounties(uint256 _resolverBounty, uint256 _prunerBounty) external onlyRole(DEFAULT_ADMIN_ROLE) {
        resolverBounty = _resolverBounty;
        prunerBounty = _prunerBounty;
        emit BountiesUpdated(_resolverBounty, _prunerBounty);
    }

    /// @notice Update the protocol fee collector address.
    /// @param _collector New collector address.
    function setProtocolFeeCollector(address _collector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_collector != address(0), "FeeModel: zero collector");
        protocolFeeCollector = _collector;
        emit ProtocolFeeCollectorUpdated(_collector);
    }
}
