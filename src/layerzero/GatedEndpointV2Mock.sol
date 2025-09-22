// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ILayerZeroEndpointV2, MessagingParams, MessagingReceipt, MessagingFee, Origin} from "./interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "./interfaces/ILayerZeroReceiver.sol";
import {Ownable} from "../utils/Ownable.sol";

/// @notice Local testing endpoint that mimics the v2 LayerZero flow while preserving
/// a gated delivery pipeline. Messages are queued on the destination endpoint,
/// verified by an authorized actor, and finally executed by a configured executor.
contract GatedEndpointV2Mock is ILayerZeroEndpointV2, Ownable {
    uint8 internal constant _NOT_ENTERED = 1;
    uint8 internal constant _ENTERED = 2;

    struct FeeConfig {
        uint128 dstGasPriceInWei;
        uint64 baseGas;
        uint64 gasPerByte;
        uint16 protocolFeeBps;
    }

    struct PendingPacket {
        Origin origin;
        bytes32 receiver;
        bytes message;
        bytes options;
        bytes32 payloadHash;
        bool verified;
        bool delivered;
    }

    struct PacketInfo {
        Origin origin;
        address receiver;
        bytes message;
        bytes options;
        bool verified;
        bool delivered;
    }

    uint32 public immutable endpointId;

    mapping(uint32 => address) public remoteEndpoints; // remote eid => endpoint address

    mapping(bytes32 => PendingPacket) internal _inbound; // guid => packet
    mapping(bytes32 => bytes32) internal _guidByKey; // keccak(srcEid, sender, receiver, nonce) => guid

    mapping(address => mapping(uint32 => mapping(bytes32 => uint64))) public outboundNonce; // sender => dstEid => receiver => nonce
    mapping(uint32 => mapping(bytes32 => uint64)) public inboundNonce; // srcEid => sender => latest nonce

    address public verifier;
    address public executor;

    address public lzTokenAddress;
    mapping(address => address) public delegates; // sender => delegate

    FeeConfig public feeConfig;
    bytes public defaultOptions;

    uint8 internal _sendEntered = _NOT_ENTERED;
    uint8 internal _receiveEntered = _NOT_ENTERED;

    event RemoteEndpointSet(uint32 indexed remoteEid, address endpoint);
    event VerifierUpdated(address indexed verifier);
    event ExecutorUpdated(address indexed executor);
    event DefaultOptionsUpdated(bytes options);
    event FeeConfigUpdated(FeeConfig config);

    modifier sendNonReentrant() {
        require(_sendEntered == _NOT_ENTERED, "LZ: send reentrancy");
        _sendEntered = _ENTERED;
        _;
        _sendEntered = _NOT_ENTERED;
    }

    modifier receiveNonReentrant() {
        require(_receiveEntered == _NOT_ENTERED, "LZ: receive reentrancy");
        _receiveEntered = _ENTERED;
        _;
        _receiveEntered = _NOT_ENTERED;
    }

    constructor(uint32 _eid) {
        endpointId = _eid;
        feeConfig = FeeConfig({
            dstGasPriceInWei: 1 gwei,
            baseGas: 100_000,
            gasPerByte: 16,
            protocolFeeBps: 100
        });
        defaultOptions = abi.encode(uint256(200_000), uint256(0));
    }

    // ---------------------------------------------------------------------
    // Admin configuration
    // ---------------------------------------------------------------------

    function setRemoteEndpoint(uint32 remoteEid, address endpoint) external onlyOwner {
        remoteEndpoints[remoteEid] = endpoint;
        emit RemoteEndpointSet(remoteEid, endpoint);
    }

    function setVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;
        emit VerifierUpdated(_verifier);
    }

    function setExecutor(address _executor) external onlyOwner {
        executor = _executor;
        emit ExecutorUpdated(_executor);
    }

    function setDefaultOptions(bytes calldata options) external onlyOwner {
        defaultOptions = options;
        emit DefaultOptionsUpdated(options);
    }

    function setFeeConfig(FeeConfig calldata config) external onlyOwner {
        feeConfig = config;
        emit FeeConfigUpdated(config);
    }

    // ---------------------------------------------------------------------
    // ILayerZeroEndpointV2 (pricing + send)
    // ---------------------------------------------------------------------

    function quote(MessagingParams calldata _params, address /*_sender*/ ) external view returns (MessagingFee memory) {
        require(!_params.payInLzToken, "LZ: lz token unsupported");
        (, uint256 nativeDrop) = _decodeOptions(_params.options);
        uint256 gasLimit = _gasLimit(_params.options);
        uint256 baseCost = uint256(feeConfig.dstGasPriceInWei) * (uint256(feeConfig.baseGas) + gasLimit);
        uint256 payloadCost = uint256(feeConfig.dstGasPriceInWei) * uint256(feeConfig.gasPerByte) * _params.message.length;
        uint256 protocolFee = (baseCost * uint256(feeConfig.protocolFeeBps)) / 10_000;
        uint256 nativeFee = baseCost + payloadCost + nativeDrop + protocolFee;
        return MessagingFee(nativeFee, 0);
    }

    function send(
        MessagingParams calldata _params,
        address _refundAddress
    ) external payable sendNonReentrant returns (MessagingReceipt memory) {
        require(!_params.payInLzToken, "LZ: lz token unsupported");
        bytes memory options;
        if (_params.options.length > 0) {
            options = _params.options;
        } else {
            options = defaultOptions;
        }
        MessagingParams memory params = MessagingParams({
            dstEid: _params.dstEid,
            receiver: _params.receiver,
            message: _params.message,
            options: options,
            payInLzToken: false
        });

        MessagingFee memory fee = this.quote(params, msg.sender);
        require(msg.value >= fee.nativeFee, "LZ: insufficient fee");

        address dstEndpoint = remoteEndpoints[params.dstEid];
        require(dstEndpoint != address(0), "LZ: dst endpoint missing");

        uint64 nonce = ++outboundNonce[msg.sender][params.dstEid][params.receiver];
        Origin memory origin = Origin({ srcEid: endpointId, sender: _toBytes32(msg.sender), nonce: nonce });
        bytes32 guid = _computeGuid(origin, params.dstEid, params.receiver);
        bytes32 payloadHash = keccak256(params.message);

        // refund excess native fee if provided
        if (msg.value > fee.nativeFee) {
            (bool success, ) = _refundAddress.call{value: msg.value - fee.nativeFee}("");
            require(success, "LZ: refund failed");
        }

        // Store the message on the destination endpoint for later verification/delivery
        GatedEndpointV2Mock(dstEndpoint)._registerInbound(origin, params.receiver, params.message, options, payloadHash, guid);

        emit PacketSent(_encodePacket(origin, params.dstEid, params.receiver, guid, params.message), options, address(this));

        return MessagingReceipt({ guid: guid, nonce: nonce, fee: fee });
    }

    // ---------------------------------------------------------------------
    // Verification + delivery pipeline
    // ---------------------------------------------------------------------

    function verify(Origin calldata _origin, address _receiver, bytes32 _payloadHash) external {
        require(msg.sender == verifier, "LZ: not verifier");
        bytes32 key = _packetKey(_origin, _toBytes32(_receiver));
        bytes32 guid = _guidByKey[key];
        require(guid != bytes32(0), "LZ: packet unknown");

        PendingPacket storage pkt = _inbound[guid];
        require(pkt.payloadHash == _payloadHash, "LZ: payload mismatch");
        require(!pkt.verified, "LZ: already verified");

        pkt.verified = true;
        emit PacketVerified(_origin, _receiver, _payloadHash);
    }

    function verifiable(Origin calldata _origin, address _receiver) external view returns (bool) {
        bytes32 key = _packetKey(_origin, _toBytes32(_receiver));
        bytes32 guid = _guidByKey[key];
        if (guid == bytes32(0)) return false;
        PendingPacket storage pkt = _inbound[guid];
        return pkt.payloadHash != bytes32(0) && !pkt.delivered;
    }

    function initializable(Origin calldata _origin, address _receiver) external view returns (bool) {
        bytes32 key = _packetKey(_origin, _toBytes32(_receiver));
        return _guidByKey[key] != bytes32(0);
    }

    function deliver(bytes32 _guid, bytes calldata _extraData) external receiveNonReentrant {
        require(msg.sender == executor, "LZ: not executor");
        _execute(_guid, _extraData, msg.sender);
    }

    function lzReceive(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable receiveNonReentrant {
        require(msg.sender == executor, "LZ: not executor");
        PendingPacket storage pkt = _inbound[_guid];
        require(pkt.payloadHash == keccak256(_message), "LZ: payload mismatch");
        require(pkt.origin.srcEid == _origin.srcEid, "LZ: src mismatch");
        require(pkt.origin.nonce == _origin.nonce, "LZ: nonce mismatch");
        require(pkt.receiver == _toBytes32(_receiver), "LZ: receiver mismatch");
        _execute(_guid, _extraData, msg.sender);
    }

    function clear(address, Origin calldata _origin, bytes32 _guid, bytes calldata) external {
        bytes32 key = _packetKey(_origin, _inbound[_guid].receiver);
        delete _guidByKey[key];
        delete _inbound[_guid];
    }

    // ---------------------------------------------------------------------
    // View helpers
    // ---------------------------------------------------------------------

    function packet(bytes32 guid) external view returns (PacketInfo memory info) {
        PendingPacket storage packet_ = _inbound[guid];
        require(packet_.payloadHash != bytes32(0), "LZ: packet missing");
        info = PacketInfo({
            origin: packet_.origin,
            receiver: _toAddress(packet_.receiver),
            message: packet_.message,
            options: packet_.options,
            verified: packet_.verified,
            delivered: packet_.delivered
        });
    }

    function guidFor(Origin calldata _origin, address _receiver) external view returns (bytes32) {
        return _guidByKey[_packetKey(_origin, _toBytes32(_receiver))];
    }

    function eid() external view returns (uint32) {
        return endpointId;
    }

    // ---------------------------------------------------------------------
    // Token / delegate management
    // ---------------------------------------------------------------------

    function setLzToken(address _lzToken) external {
        lzTokenAddress = _lzToken;
        emit LzTokenSet(_lzToken);
    }

    function lzToken() external view returns (address) {
        return lzTokenAddress;
    }

    function nativeToken() external pure returns (address) {
        return address(0);
    }

    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
        emit DelegateSet(msg.sender, _delegate);
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _registerInbound(
        Origin memory origin,
        bytes32 receiver,
        bytes memory message,
        bytes memory options,
        bytes32 payloadHash,
        bytes32 guid
    ) external {
        require(msg.sender == remoteEndpoints[origin.srcEid], "LZ: unauthorized peer");
        bytes32 key = _packetKey(origin, receiver);
        _guidByKey[key] = guid;
        _inbound[guid] = PendingPacket({
            origin: origin,
            receiver: receiver,
            message: message,
            options: options,
            payloadHash: payloadHash,
            verified: false,
            delivered: false
        });
    }

    function _execute(bytes32 guid, bytes calldata extraData, address executorAddr) internal {
        PendingPacket storage pkt = _inbound[guid];
        require(pkt.payloadHash != bytes32(0), "LZ: packet missing");
        require(pkt.verified, "LZ: not verified");
        require(!pkt.delivered, "LZ: already delivered");

        pkt.delivered = true;
        inboundNonce[pkt.origin.srcEid][pkt.origin.sender] = pkt.origin.nonce;

        address receiver = _toAddress(pkt.receiver);
        bytes memory message = pkt.message;
        ILayerZeroReceiver(receiver).lzReceive{value: 0}(pkt.origin, guid, message, executorAddr, extraData);
        emit PacketDelivered(pkt.origin, receiver);
    }

    function _encodePacket(
        Origin memory origin,
        uint32 dstEid,
        bytes32 receiver,
        bytes32 guid,
        bytes memory message
    ) internal pure returns (bytes memory) {
        return abi.encode(origin, dstEid, receiver, guid, message);
    }

    function _computeGuid(Origin memory origin, uint32 dstEid, bytes32 receiver) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(origin.nonce, origin.srcEid, origin.sender, dstEid, receiver));
    }

    function _packetKey(Origin memory origin, bytes32 receiver) internal pure returns (bytes32) {
        return keccak256(abi.encode(origin.srcEid, origin.sender, receiver, origin.nonce));
    }

    function _toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function _toAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    function _gasLimit(bytes memory options) internal view returns (uint256) {
        if (options.length == 0) {
            (uint256 defaultGas, ) = abi.decode(defaultOptions, (uint256, uint256));
            return defaultGas;
        }
        (uint256 gasLimit, ) = _decodeOptions(options);
        return gasLimit;
    }

    function _decodeOptions(bytes memory options) internal view returns (uint256 gasLimit, uint256 nativeDrop) {
        if (options.length == 0) {
            return abi.decode(defaultOptions, (uint256, uint256));
        } else if (options.length == 32) {
            gasLimit = abi.decode(options, (uint256));
            nativeDrop = 0;
        } else if (options.length == 64) {
            (gasLimit, nativeDrop) = abi.decode(options, (uint256, uint256));
        } else {
            revert("LZ: invalid options");
        }
    }
}
