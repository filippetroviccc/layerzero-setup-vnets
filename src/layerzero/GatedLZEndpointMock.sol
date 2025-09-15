// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "solidity-examples/contracts/lzApp/interfaces/ILayerZeroReceiver.sol";
import "solidity-examples/contracts/lzApp/interfaces/ILayerZeroEndpoint.sol";
import "solidity-examples/contracts/lzApp/libs/LzLib.sol";
import {Ownable} from "../utils/Ownable.sol";

interface IVerifierLike {
    function isVerified(bytes32 messageId) external view returns (bool);
}

/*
GatedLZEndpointMock
- Compatible with LayerZero apps for local testing.
- Differs from the original mock: send() enqueues messages instead of immediate delivery.
- Delivery requires:
    1) Verifier marks messageId as verified
    2) Executor contract calls deliver(messageId)
*/
contract GatedLZEndpointMock is ILayerZeroEndpoint, Ownable {
    uint8 internal constant _NOT_ENTERED = 1;
    uint8 internal constant _ENTERED = 2;

    struct ProtocolFeeConfig { uint zroFee; uint nativeBP; }
    struct RelayerFeeConfig {
        uint128 dstPriceRatio; // 10^10
        uint128 dstGasPriceInWei;
        uint128 dstNativeAmtCap;
        uint64 baseGas;
        uint64 gasPerByte;
    }

    struct PendingMessage {
        // identifiers
        uint16 dstChainId;
        uint16 srcChainId;
        address srcUa;
        address dstUa;
        uint64 nonce;
        // delivery
        uint extraGas;
        bytes path; // bytes20(srcUa) + bytes20(dstUa)
        bytes payload;
        bytes32 payloadHash;
        bool delivered;
    }

    mapping(address => address) public lzEndpointLookup; // dstUa => dst endpoint

    uint16 public mockChainId;
    RelayerFeeConfig public relayerFeeConfig;
    ProtocolFeeConfig public protocolFeeConfig;
    uint public oracleFee;
    bytes public defaultAdapterParams;

    // nonces
    mapping(uint16 => mapping(bytes => uint64)) public inboundNonce;
    mapping(uint16 => mapping(address => uint64)) public outboundNonce;

    // reentrancy guards
    uint8 internal _send_entered_state = _NOT_ENTERED;
    uint8 internal _receive_entered_state = _NOT_ENTERED;

    // gating
    address public verifier;
    address public executor;

    // queued messages
    mapping(bytes32 => PendingMessage) public pending; // messageId => message
    mapping(address => mapping(address => mapping(uint64 => bytes32))) public messageIds; // srcUa => dstUa => nonce => messageId

    event MessageQueued(bytes32 indexed messageId, uint16 indexed srcChainId, uint16 indexed dstChainId, address srcUa, address dstUa, uint64 nonce, bytes32 payloadHash);
    event MessageDelivered(bytes32 indexed messageId, address indexed executor);
    event VerifierUpdated(address indexed verifier);
    event ExecutorUpdated(address indexed executor);

    modifier sendNonReentrant() {
        require(_send_entered_state == _NOT_ENTERED, "LZMock: no send reentrancy");
        _send_entered_state = _ENTERED;
        _;
        _send_entered_state = _NOT_ENTERED;
    }

    modifier receiveNonReentrant() {
        require(_receive_entered_state == _NOT_ENTERED, "LZMock: no receive reentrancy");
        _receive_entered_state = _ENTERED;
        _;
        _receive_entered_state = _NOT_ENTERED;
    }

    constructor(uint16 _chainId) {
        mockChainId = _chainId;
        relayerFeeConfig = RelayerFeeConfig({
            dstPriceRatio: 1e10,
            dstGasPriceInWei: 1e10,
            dstNativeAmtCap: 1e19,
            baseGas: 100,
            gasPerByte: 1
        });
        protocolFeeConfig = ProtocolFeeConfig({ zroFee: 1e18, nativeBP: 1000 });
        oracleFee = 1e16;
        defaultAdapterParams = LzLib.buildDefaultAdapterParams(200000);
    }

    // Admin
    function setVerifier(address _verifier) external onlyOwner { verifier = _verifier; emit VerifierUpdated(_verifier); }
    function setExecutor(address _executor) external onlyOwner { executor = _executor; emit ExecutorUpdated(_executor); }
    function setDestLzEndpoint(address destAddr, address lzEndpointAddr) external { lzEndpointLookup[destAddr] = lzEndpointAddr; }

    // ILayerZeroEndpoint
    function send(
        uint16 _dstChainId,
        bytes memory _path,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) external payable override sendNonReentrant {
        require(_path.length == 40, "LZMock: incorrect path size");

        address dstUa;
        assembly { dstUa := mload(add(_path, 20)) }

        require(lzEndpointLookup[dstUa] != address(0), "LZMock: dest endpoint not found");

        (uint nativeFee, ) = estimateFees(
            _dstChainId,
            msg.sender,
            _payload,
            _zroPaymentAddress != address(0x0),
            _adapterParams.length > 0 ? _adapterParams : defaultAdapterParams
        );
        require(msg.value >= nativeFee, "LZMock: insufficient fee");

        uint64 nonce = ++outboundNonce[_dstChainId][msg.sender];

        // refund excess
        {
            uint refundAmt = msg.value - nativeFee;
            if (refundAmt > 0) {
                (bool success, ) = _refundAddress.call{value: refundAmt}("");
                require(success, "LZMock: refund failed");
            }
        }

        // Mock native drop
        uint extraGas = _handleAdapter(_adapterParams.length > 0 ? _adapterParams : defaultAdapterParams);

        // queue message on source endpoint; executor will relay to dest endpoint
        bytes32 messageId = _enqueue(dstUa, _dstChainId, nonce, extraGas, _payload);

        emit MessageQueued(messageId, mockChainId, _dstChainId, msg.sender, dstUa, nonce, pending[messageId].payloadHash);
    }

    function deliver(bytes32 messageId) external {
        require(msg.sender == executor, "not executor");
        PendingMessage storage m = pending[messageId];
        require(!m.delivered, "already delivered");
        require(m.payload.length > 0, "unknown msg");
        require(verifier != address(0), "no verifier");
        require(IVerifierLike(verifier).isVerified(messageId), "not verified");

        address dstEndpoint = lzEndpointLookup[m.dstUa];
        require(dstEndpoint != address(0), "dest endpoint missing");

        // deliver to destination endpoint
        GatedLZEndpointMock(dstEndpoint).receivePayload(m.srcChainId, m.path, m.dstUa, m.nonce, m.extraGas, m.payload);
        m.delivered = true;
        emit MessageDelivered(messageId, msg.sender);
    }

    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _path,
        address _dstAddress,
        uint64 _nonce,
        uint _gasLimit,
        bytes calldata _payload
    ) public override receiveNonReentrant {
        // assert and increment the nonce. no message shuffling
        require(_nonce == ++inboundNonce[_srcChainId][_path], "LZMock: wrong nonce");

        try ILayerZeroReceiver(_dstAddress).lzReceive{gas: _gasLimit}(_srcChainId, _path, _nonce, _payload) {
        } catch {
            // swallow for mock simplicity
            ILayerZeroReceiver(_dstAddress).lzReceive(_srcChainId, _path, _nonce, _payload);
        }
    }

    // View interface impls
    function getInboundNonce(uint16 _chainID, bytes calldata _path) external view override returns (uint64) {
        return inboundNonce[_chainID][_path];
    }

    function getOutboundNonce(uint16 _chainID, address _srcAddress) external view override returns (uint64) {
        return outboundNonce[_chainID][_srcAddress];
    }

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes memory _payload,
        bool _payInZRO,
        bytes memory _adapterParams
    ) public view override returns (uint nativeFee, uint zroFee) {
        bytes memory adapterParams = _adapterParams.length > 0 ? _adapterParams : defaultAdapterParams;
        uint relayerFee = _getRelayerFee(_dstChainId, 1, _userApplication, _payload.length, adapterParams);
        uint protocolFee = _getProtocolFees(_payInZRO, relayerFee, oracleFee);
        _payInZRO ? zroFee = protocolFee : nativeFee = protocolFee;
        nativeFee = nativeFee + relayerFee + oracleFee;
    }

    function getChainId() external view override returns (uint16) { return mockChainId; }

    function retryPayload(uint16, bytes calldata, bytes calldata) external pure override { revert("unused"); }
    function hasStoredPayload(uint16, bytes calldata) external pure override returns (bool) { return false; }
    function getSendLibraryAddress(address) external view override returns (address) { return address(this); }
    function getReceiveLibraryAddress(address) external view override returns (address) { return address(this); }
    function isSendingPayload() external view override returns (bool) { return _send_entered_state == _ENTERED; }
    function isReceivingPayload() external view override returns (bool) { return _receive_entered_state == _ENTERED; }
    function getConfig(uint16, uint16, address, uint) external pure override returns (bytes memory) { return ""; }
    function getSendVersion(address) external pure override returns (uint16) { return 1; }
    function getReceiveVersion(address) external pure override returns (uint16) { return 1; }
    function setConfig(uint16, uint16, uint, bytes memory) external override {}
    function setSendVersion(uint16) external override {}
    function setReceiveVersion(uint16) external override {}
    function forceResumeReceive(uint16, bytes calldata) external override {}

    // Fee helpers
    function setRelayerPrice(uint128 _dstPriceRatio, uint128 _dstGasPriceInWei, uint128 _dstNativeAmtCap, uint64 _baseGas, uint64 _gasPerByte) external {
        relayerFeeConfig.dstPriceRatio = _dstPriceRatio;
        relayerFeeConfig.dstGasPriceInWei = _dstGasPriceInWei;
        relayerFeeConfig.dstNativeAmtCap = _dstNativeAmtCap;
        relayerFeeConfig.baseGas = _baseGas;
        relayerFeeConfig.gasPerByte = _gasPerByte;
    }
    function setProtocolFee(uint _zroFee, uint _nativeBP) external { protocolFeeConfig.zroFee = _zroFee; protocolFeeConfig.nativeBP = _nativeBP; }
    function setOracleFee(uint _oracleFee) external { oracleFee = _oracleFee; }
    function setDefaultAdapterParams(bytes memory _adapterParams) external { defaultAdapterParams = _adapterParams; }

    function _getProtocolFees(bool _payInZro, uint _relayerFee, uint _oracleFee) internal view returns (uint) {
        if (_payInZro) return protocolFeeConfig.zroFee;
        return ((_relayerFee + _oracleFee) * protocolFeeConfig.nativeBP) / 10000;
    }

    function _getRelayerFee(
        uint16, /* _dstChainId */
        uint16, /* _outboundProofType */
        address, /* _userApplication */
        uint _payloadSize,
        bytes memory _adapterParams
    ) internal view returns (uint) {
        (uint16 txType, uint extraGas, uint dstNativeAmt, ) = LzLib.decodeAdapterParams(_adapterParams);
        uint totalRemoteToken;
        if (txType == 2) {
            require(relayerFeeConfig.dstNativeAmtCap >= dstNativeAmt, "LZMock: dstNativeAmt too large");
            totalRemoteToken += dstNativeAmt;
        }
        uint remoteGasTotal = relayerFeeConfig.dstGasPriceInWei * (relayerFeeConfig.baseGas + extraGas);
        totalRemoteToken += remoteGasTotal;
        uint basePrice = (totalRemoteToken * relayerFeeConfig.dstPriceRatio) / 10**10;
        uint pricePerByte = (relayerFeeConfig.dstGasPriceInWei * relayerFeeConfig.gasPerByte * relayerFeeConfig.dstPriceRatio) / 10**10;
        return basePrice + _payloadSize * pricePerByte;
    }

    function _computeMessageId(
        address srcUa,
        uint16 srcChainId,
        uint16 dstChainId,
        address dstUa,
        uint64 nonce,
        bytes32 payloadHash
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(srcChainId, srcUa, dstChainId, dstUa, nonce, payloadHash));
    }

    function _handleAdapter(bytes memory adapterParams) internal returns (uint extraGas) {
        uint dstNativeAmt; address payable dstNativeAddr;
        (, extraGas, dstNativeAmt, dstNativeAddr) = LzLib.decodeAdapterParams(adapterParams);
        if (dstNativeAmt > 0) {
            (bool ok, ) = dstNativeAddr.call{value: dstNativeAmt}("");
            ok;
        }
    }

    function _enqueue(
        address dstUa,
        uint16 dstChainId,
        uint64 nonce,
        uint extraGas,
        bytes calldata payload
    ) internal returns (bytes32 messageId) {
        bytes32 pHash = keccak256(payload);
        messageId = _computeMessageId(msg.sender, mockChainId, dstChainId, dstUa, nonce, pHash);
        pending[messageId] = PendingMessage({
            dstChainId: dstChainId,
            srcChainId: mockChainId,
            srcUa: msg.sender,
            dstUa: dstUa,
            nonce: nonce,
            extraGas: extraGas,
            path: abi.encodePacked(msg.sender, dstUa),
            payload: payload,
            payloadHash: pHash,
            delivered: false
        });
        messageIds[msg.sender][dstUa][nonce] = messageId;
    }
}
