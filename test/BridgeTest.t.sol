// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatedEndpointV2Mock} from "../src/layerzero/GatedEndpointV2Mock.sol";
import {TokenA} from "../src/tokens/TokenA.sol";
import {OFT_A} from "../src/oft/OFT_A.sol";
import {OFT_B} from "../src/oft/OFT_B.sol";
import {Executor} from "../src/infra/Executor.sol";
import {MessagingFee, MessagingReceipt} from "../src/layerzero/interfaces/ILayerZeroEndpointV2.sol";

contract BridgeTest {
    uint32 constant EID_A = 101;
    uint32 constant EID_B = 102;

    GatedEndpointV2Mock endpointA;
    GatedEndpointV2Mock endpointB;
    TokenA tokenA;
    OFT_A oftA;
    OFT_B oftB;
    Executor executorA;
    Executor executorB;

    function setUp() public {
        endpointA = new GatedEndpointV2Mock(EID_A);
        endpointB = new GatedEndpointV2Mock(EID_B);

        endpointA.setRemoteEndpoint(EID_B, address(endpointB));
        endpointB.setRemoteEndpoint(EID_A, address(endpointA));

        tokenA = new TokenA();

        bytes memory defaultOptions = abi.encode(uint256(200_000), uint256(0));
        oftA = new OFT_A(address(tokenA), address(endpointA), defaultOptions);
        oftB = new OFT_B("TokenA", "TKA", address(endpointB), defaultOptions);

        oftA.setPeer(EID_B, _toBytes32(address(oftB)));
        oftB.setPeer(EID_A, _toBytes32(address(oftA)));

        executorA = new Executor(address(endpointA));
        executorB = new Executor(address(endpointB));
        endpointA.setExecutor(address(executorA));
        endpointB.setExecutor(address(executorB));

        endpointA.setVerifier(address(this));
        endpointB.setVerifier(address(this));
    }

    function testBridgeFlow() public {
        setUp();

        tokenA.ownerMint(address(this), 1_000 ether);
        tokenA.approve(address(oftA), 1_000 ether);

        bytes memory options = abi.encode(uint256(200_000), uint256(0));
        MessagingFee memory fee = oftA.quoteSend(EID_B, address(this), 250 ether, options);

        MessagingReceipt memory receipt = oftA.send{value: fee.nativeFee}(EID_B, address(this), 250 ether, options);

        require(tokenA.balanceOf(address(this)) == 750 ether, "balance A mismatch after send");
        require(oftB.balanceOf(address(this)) == 0, "balance B should be 0 before delivery");

        GatedEndpointV2Mock.PacketInfo memory packet = endpointB.packet(receipt.guid);
        endpointB.verify(packet.origin, packet.receiver, keccak256(packet.message));

        executorB.execute(receipt.guid);

        require(oftB.balanceOf(address(this)) == 250 ether, "balance B mismatch after delivery");
        require(endpointB.packet(receipt.guid).delivered == true, "packet should be marked delivered");
    }

    function _toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }
}
