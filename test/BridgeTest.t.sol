// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GatedLZEndpointMock} from "../src/layerzero/GatedLZEndpointMock.sol";
import {TokenA} from "../src/tokens/TokenA.sol";
import {OFT_A} from "../src/oft/OFT_A.sol";
import {OFT_B} from "../src/oft/OFT_B.sol";
import {ICommonOFT} from "solidity-examples/contracts/token/oft/v2/interfaces/ICommonOFT.sol";
import {Verifier} from "../src/infra/Verifier.sol";
import {Executor} from "../src/infra/Executor.sol";

contract BridgeTest {
    uint16 constant CHAIN_A = 101;
    uint16 constant CHAIN_B = 102;

    GatedLZEndpointMock endpointA;
    GatedLZEndpointMock endpointB;
    TokenA tokenA;
    OFT_A oftA; // proxy on chain A (locks TokenA)
    OFT_B oftB; // minted representation on chain B
    Verifier verifierA;
    Verifier verifierB;
    Executor execA;
    Executor execB;

    function setUp() public {
        endpointA = new GatedLZEndpointMock(CHAIN_A);
        endpointB = new GatedLZEndpointMock(CHAIN_B);

        tokenA = new TokenA();
        oftA = new OFT_A(address(tokenA), 18, address(endpointA));
        oftB = new OFT_B("TokenA", "TKA", 18, address(endpointB));

        // wire endpoints
        endpointA.setDestLzEndpoint(address(oftB), address(endpointB));
        endpointB.setDestLzEndpoint(address(oftA), address(endpointA));

        // configure trusted paths and gas
        bytes memory pathAtoB = abi.encodePacked(address(oftB), address(oftA));
        bytes memory pathBtoA = abi.encodePacked(address(oftA), address(oftB));
        oftA.setMinDstGas(CHAIN_B, 0, 200000);
        oftA.setMinDstGas(CHAIN_B, 1, 200000);
        oftB.setMinDstGas(CHAIN_A, 0, 200000);
        oftB.setMinDstGas(CHAIN_A, 1, 200000);
        oftA.setTrustedRemote(CHAIN_B, pathAtoB);
        oftB.setTrustedRemote(CHAIN_A, pathBtoA);

        // infra
        verifierA = new Verifier();
        verifierB = new Verifier();
        execA = new Executor(address(endpointA));
        execB = new Executor(address(endpointB));
        endpointA.setVerifier(address(verifierA));
        endpointB.setVerifier(address(verifierB));
        endpointA.setExecutor(address(execA));
        endpointB.setExecutor(address(execB));
    }

    function testBridgeFlow() public {
        setUp();

        // Mint 1000 on chain A to this contract
        tokenA.ownerMint(address(this), 1000 ether);

        // Approve OFT_A to spend
        tokenA.approve(address(oftA), 1000 ether);

        // Build adapter params (version=1, gas=200000)
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(200000));

        // Estimate fee and send to chain B
        (uint nativeFee, ) = oftA.estimateSendFee(CHAIN_B, _toBytes32(address(this)), 250 ether, false, adapterParams);

        ICommonOFT.LzCallParams memory callParams = ICommonOFT.LzCallParams({
            refundAddress: payable(address(this)),
            zroPaymentAddress: address(0),
            adapterParams: adapterParams
        });

        oftA.sendFrom{value: nativeFee}(
            address(this),
            CHAIN_B,
            _toBytes32(address(this)),
            250 ether,
            callParams
        );

        // After send, nothing minted yet on B until verifier+executor run
        require(tokenA.balanceOf(address(this)) == 750 ether, "balance A mismatch after send");
        require(oftB.balanceOf(address(this)) == 0, "balance B should be 0 before exec");

        // Off-chain analogue: compute messageId and verify + execute
        uint64 nonce = endpointA.getOutboundNonce(CHAIN_B, address(oftA));
        bytes32 msgId = endpointA.messageIds(address(oftA), address(oftB), nonce);
        verifierA.submitAttestation(msgId);
        execA.execute(msgId);

        // Now balance should reflect minted amount on B
        require(oftB.balanceOf(address(this)) == 250 ether, "balance B mismatch after exec");
    }

    function _toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }
}
