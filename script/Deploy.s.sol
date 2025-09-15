// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NOTE: Placeholder deploy helper; not a forge-std Script.

import "solidity-examples/contracts/lzApp/mocks/LZEndpointMock.sol";
import {TokenA} from "../src/tokens/TokenA.sol";
import {OFT_A} from "../src/oft/OFT_A.sol";
import {OFT_B} from "../src/oft/OFT_B.sol";
import {ICommonOFT} from "solidity-examples/contracts/token/oft/v2/interfaces/ICommonOFT.sol";

contract DeployAll {
    struct Deployed {
        address endpointA;
        address endpointB;
        address tokenA;
        address oftA;
        address oftB;
    }

    function deploy() external returns (Deployed memory d) {
        LZEndpointMock epA = new LZEndpointMock(101);
        LZEndpointMock epB = new LZEndpointMock(102);

        TokenA tA = new TokenA();

        // sharedDecimals set to 18 for simplicity
        OFT_A oA = new OFT_A(address(tA), 18, address(epA));
        OFT_B oB = new OFT_B("TokenA", "TKA", 18, address(epB));

        // wire endpoints for the two UAs
        epA.setDestLzEndpoint(address(oB), address(epB));
        epB.setDestLzEndpoint(address(oA), address(epA));

        // set trusted remotes and min gas
        bytes memory remotePathAtoB = abi.encodePacked(address(oB), address(oA));
        bytes memory remotePathBtoA = abi.encodePacked(address(oA), address(oB));
        oA.setMinDstGas(102, 0, 200000);
        oA.setMinDstGas(102, 1, 200000);
        oB.setMinDstGas(101, 0, 200000);
        oB.setMinDstGas(101, 1, 200000);
        oA.setTrustedRemote(102, remotePathAtoB);
        oB.setTrustedRemote(101, remotePathBtoA);

        d = Deployed(address(epA), address(epB), address(tA), address(oA), address(oB));
    }
}
