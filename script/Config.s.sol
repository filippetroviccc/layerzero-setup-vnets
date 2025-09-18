// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Placeholder config script. In a full setup, use forge-std Script to
// connect to two RPCs and wire endpoints, peers, and executors.

contract Config {
    function wireEndpoints(address endpointA, address endpointB, uint32 eidA, uint32 eidB) external {
        IEndpoint(endpointA).setRemoteEndpoint(eidB, endpointB);
        IEndpoint(endpointB).setRemoteEndpoint(eidA, endpointA);
    }

    function setPeers(address oftA, address oftB, uint32 eidA, uint32 eidB) external {
        IOFT(oftA).setPeer(eidB, _toBytes32(oftB));
        IOFT(oftB).setPeer(eidA, _toBytes32(oftA));
    }

    function _toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }
}

interface IEndpoint {
    function setRemoteEndpoint(uint32 remoteEid, address endpoint) external;
}

interface IOFT {
    function setPeer(uint32 eid, bytes32 peer) external;
}
