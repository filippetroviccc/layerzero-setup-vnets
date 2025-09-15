// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "../utils/Ownable.sol";

interface IGatedEndpoint {
    function deliver(bytes32 messageId) external;
}

// Minimal executor contract: invoked by off-chain agent to trigger delivery.
// Endpoint authorizes this contract as its executor.
contract Executor is Ownable {
    address public endpoint; // Gated endpoint on the source chain

    event Delivered(bytes32 indexed messageId);
    event EndpointUpdated(address indexed endpoint);

    constructor(address _endpoint) {
        endpoint = _endpoint;
        emit EndpointUpdated(_endpoint);
    }

    function setEndpoint(address _endpoint) external onlyOwner {
        endpoint = _endpoint;
        emit EndpointUpdated(_endpoint);
    }

    function execute(bytes32 messageId) external {
        IGatedEndpoint(endpoint).deliver(messageId);
        emit Delivered(messageId);
    }
}

