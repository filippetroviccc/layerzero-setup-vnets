// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "../utils/Ownable.sol";

// Simple local Verifier: off-chain agent submits attestations for message ids.
contract Verifier is Ownable {
    event Verified(bytes32 indexed messageId, address indexed submitter);

    mapping(bytes32 => bool) public isVerified; // messageId => verified

    // In local dev, allow anyone to submit. In prod, gate by role.
    function submitAttestation(bytes32 messageId) external {
        isVerified[messageId] = true;
        emit Verified(messageId, msg.sender);
    }
}

