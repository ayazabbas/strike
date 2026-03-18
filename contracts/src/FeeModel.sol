// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title FeeModel
/// @notice Fee-calculation contract for the Strike CLOB protocol.
///
///         Fee schedule
///         ------------
///         feeBps             — uniform fee in basis points (e.g. 20 = 0.20%)
///         protocolFeeCollector — address that receives protocol fee share
contract FeeModel is AccessControl {
    uint256 public constant MAX_BPS = 10_000;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    uint256 public feeBps;
    address public protocolFeeCollector;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event FeeBpsUpdated(uint256 feeBps);
    event ProtocolFeeCollectorUpdated(address indexed collector);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(
        address admin,
        uint256 _feeBps,
        address _protocolFeeCollector
    ) {
        require(_feeBps <= MAX_BPS, "FeeModel: fee > 100%");
        require(_protocolFeeCollector != address(0), "FeeModel: zero collector");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        feeBps = _feeBps;
        protocolFeeCollector = _protocolFeeCollector;
    }

    // -------------------------------------------------------------------------
    // Fee calculations
    // -------------------------------------------------------------------------

    /// @notice Returns the uniform fee for a given trade amount.
    function calculateFee(uint256 amount) public view returns (uint256 fee) {
        fee = (amount * feeBps) / MAX_BPS;
    }

    // -------------------------------------------------------------------------
    // Admin parameter updates
    // -------------------------------------------------------------------------

    function setFeeBps(uint256 _feeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feeBps <= MAX_BPS, "FeeModel: fee > 100%");
        feeBps = _feeBps;
        emit FeeBpsUpdated(_feeBps);
    }

    function setProtocolFeeCollector(address _collector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_collector != address(0), "FeeModel: zero collector");
        protocolFeeCollector = _collector;
        emit ProtocolFeeCollectorUpdated(_collector);
    }
}
