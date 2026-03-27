// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IFlapAIProvider {
    struct Model {
        string name;
        uint256 price;
        bool enabled;
    }

    function getModel(uint256 modelId) external view returns (Model memory);
    function reason(uint256 modelId, string calldata prompt, uint8 numChoices) external payable returns (uint256 requestId);
    function getReasoningCid(uint256 requestId) external view returns (string memory);
    function getRequest(uint256 requestId) external view returns (bytes memory);
}

abstract contract FlapAIConsumerBase {
    error FlapAIConsumerOnlyProvider();
    error FlapAIConsumerUnsupportedChain(uint256 chainId);

    modifier onlyFlapAIProvider() {
        if (msg.sender != _getFlapAIProvider()) revert FlapAIConsumerOnlyProvider();
        _;
    }

    function _getFlapAIProvider() internal view virtual returns (address) {
        uint256 id = block.chainid;
        if (id == 56) {
            return 0xaEe3a7Ca6fe6b53f6c32a3e8407eC5A9dF8B7E39;
        } else if (id == 97) {
            return 0xFfddcE44e8cFf7703Fd85118524bfC8B2f70b744;
        } else {
            revert FlapAIConsumerUnsupportedChain(id);
        }
    }

    function lastRequestId() external view virtual returns (uint256);

    function fulfillReasoning(uint256 requestId, uint8 choice) external onlyFlapAIProvider {
        _fulfillReasoning(requestId, choice);
    }

    function onFlapAIRequestRefunded(uint256 requestId) external payable onlyFlapAIProvider {
        _onFlapAIRequestRefunded(requestId);
    }

    function _fulfillReasoning(uint256 requestId, uint8 choice) internal virtual;
    function _onFlapAIRequestRefunded(uint256 requestId) internal virtual;
}
