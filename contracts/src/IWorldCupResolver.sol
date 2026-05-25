// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Minimal adapter surface for Flap's WorldCupResolver outcome statuses.
interface IWorldCupResolver {
    function getOutcomeStatus(uint8 outcomeId) external view returns (bool isReported, bool result, bool isFlagged);
}
