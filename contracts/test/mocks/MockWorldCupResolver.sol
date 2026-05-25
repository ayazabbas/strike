// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../../src/IWorldCupResolver.sol";

contract MockWorldCupResolver is IWorldCupResolver {
    struct Status {
        bool isReported;
        bool result;
        bool isFlagged;
    }

    mapping(uint8 => Status) internal _statuses;
    bool public shouldRevert;

    function setStatus(uint8 outcomeId, bool isReported, bool result, bool isFlagged) external {
        _statuses[outcomeId] = Status({isReported: isReported, result: result, isFlagged: isFlagged});
    }

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function getOutcomeStatus(uint8 outcomeId) external view returns (bool isReported, bool result, bool isFlagged) {
        if (shouldRevert) {
            revert("resolver paused");
        }
        Status memory status = _statuses[outcomeId];
        return (status.isReported, status.result, status.isFlagged);
    }
}
