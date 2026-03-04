// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "pyth-lazer-sdk/IPythLazer.sol";

/// @title MockPyth
/// @notice Minimal mock of the Pyth Lazer verifier for local devnet testing.
///         Stores price data per feedId and returns a valid Pyth Lazer payload
///         when verifyUpdate is called. Callers pass abi.encode(uint32 feedId)
///         as the update bytes.
contract MockPyth is IPythLazer {
    address public admin;

    struct PriceData {
        int64 price;
        uint64 conf;
        uint64 publishTime;
    }

    mapping(uint32 => PriceData) public prices;

    constructor() {
        admin = msg.sender;
    }

    /// @notice Store a price for a feed ID. Admin only.
    function setPrice(uint32 feedId, int64 price, uint64 conf, uint64 publishTime) external {
        require(msg.sender == admin, "MockPyth: not admin");
        prices[feedId] = PriceData(price, conf, publishTime);
    }

    /// @notice Always zero — no fee for local testing.
    function verification_fee() external pure returns (uint256) {
        return 0;
    }

    /// @notice Decode feedId from update bytes, build a valid Pyth Lazer payload.
    /// @param update ABI-encoded uint32 feedId (use abi.encode(uint32(feedId))).
    function verifyUpdate(bytes calldata update)
        external
        payable
        returns (bytes memory payload, address signer)
    {
        uint32 feedId = abi.decode(update, (uint32));
        PriceData memory d = prices[feedId];
        require(d.publishTime > 0, "MockPyth: no price set for feed");

        // Build binary payload matching PythLazerLib.parseUpdateFromPayload format:
        //   magic(4) + timestamp(8) + channel(1) + feedsLen(1)
        //   + feedId(4) + numProps(1) + [propId(1) + price(8)] + [propId(1) + conf(8)]
        //   = 37 bytes total
        payload = abi.encodePacked(
            uint32(2479346549),  // FORMAT_MAGIC
            uint64(d.publishTime),
            uint8(1),            // channel: RealTime
            uint8(1),            // feedsLen
            feedId,
            uint8(2),            // numProperties (Price + Confidence)
            uint8(0),            // propertyId: Price
            d.price,
            uint8(5),            // propertyId: Confidence
            d.conf
        );
        signer = msg.sender;
    }
}
