// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NOTE: Placeholder deploy helper; not a forge-std Script.

import {GatedEndpointV2Mock} from "../src/layerzero/GatedEndpointV2Mock.sol";
import {TokenA} from "../src/tokens/TokenA.sol";
import {OFT_A} from "../src/oft/OFT_A.sol";
import {OFT_B} from "../src/oft/OFT_B.sol";
import {Executor} from "../src/infra/Executor.sol";

contract DeployAll {
    struct Deployed {
        address endpointA;
        address endpointB;
        address tokenA;
        address oftA;
        address oftB;
        address executorA;
        address executorB;
    }

    function deploy() external returns (Deployed memory d) {
        GatedEndpointV2Mock epA = new GatedEndpointV2Mock(101);
        GatedEndpointV2Mock epB = new GatedEndpointV2Mock(102);

        epA.setRemoteEndpoint(102, address(epB));
        epB.setRemoteEndpoint(101, address(epA));

        TokenA tA = new TokenA();
        bytes memory defaultOptions = abi.encode(uint256(200_000), uint256(0));

        OFT_A oA = new OFT_A(address(tA), address(epA), defaultOptions);
        OFT_B oB = new OFT_B("TokenA", "TKA", address(epB), defaultOptions);

        oA.setPeer(102, _toBytes32(address(oB)));
        oB.setPeer(101, _toBytes32(address(oA)));

        Executor exA = new Executor(address(epA));
        Executor exB = new Executor(address(epB));
        epA.setExecutor(address(exA));
        epB.setExecutor(address(exB));

        epA.setVerifier(msg.sender);
        epB.setVerifier(msg.sender);

        d = Deployed({
            endpointA: address(epA),
            endpointB: address(epB),
            tokenA: address(tA),
            oftA: address(oA),
            oftB: address(oB),
            executorA: address(exA),
            executorB: address(exB)
        });
    }

    function _toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }
}
