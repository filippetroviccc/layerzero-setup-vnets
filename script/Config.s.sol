// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Placeholder config script. In a full setup, use forge-std Script to
// connect to two RPCs and wire endpoints + trusted remotes.

import "solidity-examples/contracts/lzApp/mocks/LZEndpointMock.sol";
import {ICommonOFT} from "solidity-examples/contracts/token/oft/v2/interfaces/ICommonOFT.sol";

contract Config {
    function setRemotes(address endpointA, address endpointB, address oftA, address oftB) external {
        LZEndpointMock(endpointA).setDestLzEndpoint(oftB, endpointB);
        LZEndpointMock(endpointB).setDestLzEndpoint(oftA, endpointA);
    }

    function setTrustedRemotes(address oftA, address oftB) external {
        bytes memory pathAtoB = abi.encodePacked(oftB, oftA);
        bytes memory pathBtoA = abi.encodePacked(oftA, oftB);
        LzAppLike(oftA).setMinDstGas(102, 0, 200000);
        LzAppLike(oftA).setMinDstGas(102, 1, 200000);
        LzAppLike(oftB).setMinDstGas(101, 0, 200000);
        LzAppLike(oftB).setMinDstGas(101, 1, 200000);
        LzAppLike(oftA).setTrustedRemote(102, pathAtoB);
        LzAppLike(oftB).setTrustedRemote(101, pathBtoA);
    }
}

interface LzAppLike {
    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external;
    function setMinDstGas(uint16 _dstChainId, uint16 _packetType, uint _minGas) external;
}
