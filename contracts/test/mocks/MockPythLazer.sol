// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title MockPythLazer
/// @notice Mock for testing. Skips signature verification — treats update bytes
///         as the raw Lazer payload and returns them directly.
contract MockPythLazer {
    uint256 public verification_fee;

    constructor(uint256 _fee) {
        verification_fee = _fee;
    }

    function verifyUpdate(bytes calldata update)
        external
        payable
        returns (bytes memory payload, address signer)
    {
        require(msg.value >= verification_fee, "Insufficient fee");
        if (msg.value > verification_fee) {
            payable(msg.sender).transfer(msg.value - verification_fee);
        }
        payload = update;
        signer = address(0x1234);
    }
}
