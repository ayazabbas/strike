// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./flap/IFlapAIProvider.sol";

/// @notice Test-only mock of the Flap AI oracle provider.
contract MockFlapAIProvider {
    mapping(uint256 => uint256) public modelPrices;
    uint256 public nextRequestId = 1;

    constructor() {
        modelPrices[0] = 0.01 ether;
        modelPrices[1] = 0.05 ether;
        modelPrices[2] = 0.03 ether;
    }

    function getModel(uint256 modelId) external view returns (IFlapAIProvider.Model memory) {
        return IFlapAIProvider.Model("mock", modelPrices[modelId], true);
    }

    function reason(uint256, string calldata, uint8) external payable returns (uint256) {
        uint256 id = nextRequestId++;
        return id;
    }

    function setPrice(uint256 modelId, uint256 price) external {
        modelPrices[modelId] = price;
    }

    /// @notice Simulate oracle callback — fulfill with choice
    function fulfill(address consumer, uint256 requestId, uint8 choice) external {
        FlapAIConsumerBase(consumer).fulfillReasoning(requestId, choice);
    }

    /// @notice Simulate oracle refund callback
    function refund(address consumer, uint256 requestId) external {
        FlapAIConsumerBase(consumer).onFlapAIRequestRefunded{value: 0}(requestId);
    }

    function getReasoningCid(uint256) external pure returns (string memory) {
        return "";
    }

    function getRequest(uint256) external pure returns (bytes memory) {
        return "";
    }

    receive() external payable {}
}
