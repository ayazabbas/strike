// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IPythLazer
/// @notice Minimal interface for the Pyth Lazer on-chain verifier.
interface IPythLazer {
    /// @notice Verify a Pyth Lazer update and return the verified payload.
    /// @param update The signed update bytes (EVM format).
    /// @return payload The verified payload bytes.
    /// @return signer The address of the trusted signer.
    function verifyUpdate(bytes calldata update)
        external
        payable
        returns (bytes memory payload, address signer);

    /// @notice The fee required for verification.
    function verification_fee() external view returns (uint256);
}
