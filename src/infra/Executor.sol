// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "../utils/Ownable.sol";

interface IGatedEndpointV2 {
    function deliver(bytes32 guid, bytes calldata extraData) external;
}

/// @notice Minimal executor contract. An off-chain agent triggers execute() to
/// request delivery of a verified packet on the destination endpoint.
contract Executor is Ownable {
    address public endpoint; // endpoint that authorizes this executor

    event Delivered(bytes32 indexed guid);
    event EndpointUpdated(address indexed endpoint);

    constructor(address _endpoint) {
        endpoint = _endpoint;
        emit EndpointUpdated(_endpoint);
    }

    function setEndpoint(address _endpoint) external onlyOwner {
        endpoint = _endpoint;
        emit EndpointUpdated(_endpoint);
    }

    function execute(bytes32 guid) external {
        IGatedEndpointV2(endpoint).deliver(guid, bytes(""));
        emit Delivered(guid);
    }
}
