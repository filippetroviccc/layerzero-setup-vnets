// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILayerZeroEndpointV2, MessagingParams, MessagingReceipt, MessagingFee, Origin} from "../layerzero/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "../layerzero/interfaces/ILayerZeroReceiver.sol";
import {Ownable} from "../utils/Ownable.sol";

/// @notice Minimal OFT base contract compatible with the GatedEndpointV2Mock.
/// Derived contracts implement token-specific debit/credit logic.
abstract contract BaseOFTV2 is Ownable, ILayerZeroReceiver {
    ILayerZeroEndpointV2 public immutable endpoint;
    bytes public defaultOptions;

    mapping(uint32 => bytes32) public peers;
    mapping(uint32 => mapping(bytes32 => uint64)) public inboundNonce;

    event PeerSet(uint32 indexed eid, bytes32 indexed peer);
    event DefaultOptionsSet(bytes options);
    event OFTSent(bytes32 guid, uint32 indexed dstEid, address indexed sender, address indexed recipient, uint256 amount);
    event OFTReceived(bytes32 guid, uint32 indexed srcEid, address indexed recipient, uint256 amount);

    constructor(address _endpoint, bytes memory _defaultOptions) {
        endpoint = ILayerZeroEndpointV2(_endpoint);
        defaultOptions = _defaultOptions.length > 0 ? _defaultOptions : abi.encode(uint256(200_000), uint256(0));
    }

    // ---------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------

    function setPeer(uint32 eid, bytes32 peer) external onlyOwner {
        peers[eid] = peer;
        emit PeerSet(eid, peer);
    }

    function setDefaultOptions(bytes calldata options) external onlyOwner {
        defaultOptions = options;
        emit DefaultOptionsSet(options);
    }

    // ---------------------------------------------------------------------
    // LayerZero receiver interface
    // ---------------------------------------------------------------------

    function allowInitializePath(Origin calldata _origin) external view returns (bool) {
        return peers[_origin.srcEid] == _origin.sender;
    }

    function nextNonce(uint32 _eid, bytes32 _sender) external view returns (uint64) {
        return inboundNonce[_eid][_sender] + 1;
    }

    // ---------------------------------------------------------------------
    // Public helpers
    // ---------------------------------------------------------------------

    function quoteSend(uint32 dstEid, address to, uint256 amountLD, bytes calldata options) public view returns (MessagingFee memory) {
        bytes memory message = _encodeMessage(to, amountLD);
        bytes memory opts;
        if (options.length > 0) {
            opts = options;
        } else {
            opts = defaultOptions;
        }
        bytes32 peer = peers[dstEid];
        require(peer != bytes32(0), "OFT: peer not set");
        MessagingParams memory params = MessagingParams({
            dstEid: dstEid,
            receiver: peer,
            message: message,
            options: opts,
            payInLzToken: false
        });
        return endpoint.quote(params, address(this));
    }

    function send(uint32 dstEid, address to, uint256 amountLD, bytes calldata options) external payable returns (MessagingReceipt memory) {
        _debit(msg.sender, amountLD, dstEid);

        bytes memory message = _encodeMessage(to, amountLD);
        bytes memory opts;
        if (options.length > 0) {
            opts = options;
        } else {
            opts = defaultOptions;
        }
        bytes32 peer = peers[dstEid];
        require(peer != bytes32(0), "OFT: peer not set");

        MessagingParams memory params = MessagingParams({
            dstEid: dstEid,
            receiver: peer,
            message: message,
            options: opts,
            payInLzToken: false
        });

        MessagingFee memory fee = endpoint.quote(params, address(this));
        require(msg.value >= fee.nativeFee, "OFT: insufficient fee");

        MessagingReceipt memory receipt = endpoint.send{value: fee.nativeFee}(params, msg.sender);

        if (msg.value > fee.nativeFee) {
            payable(msg.sender).transfer(msg.value - fee.nativeFee);
        }

        emit OFTSent(receipt.guid, dstEid, msg.sender, to, amountLD);
        return receipt;
    }

    // ---------------------------------------------------------------------
    // Receive hook from the endpoint
    // ---------------------------------------------------------------------

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        require(msg.sender == address(endpoint), "OFT: invalid endpoint");
        require(peers[_origin.srcEid] == _origin.sender, "OFT: invalid sender");

        inboundNonce[_origin.srcEid][_origin.sender] = _origin.nonce;

        (address to, uint256 amountLD) = _decodeMessage(_message);
        _credit(to, amountLD, _origin.srcEid);
        _afterReceive(_origin, _guid, to, amountLD, _executor, _extraData);

        emit OFTReceived(_guid, _origin.srcEid, to, amountLD);
    }

    // ---------------------------------------------------------------------
    // Internal extension points
    // ---------------------------------------------------------------------

    function _encodeMessage(address to, uint256 amountLD) internal pure virtual returns (bytes memory) {
        return abi.encode(to, amountLD);
    }

    function _decodeMessage(bytes memory message) internal pure virtual returns (address to, uint256 amountLD) {
        return abi.decode(message, (address, uint256));
    }

    function _afterReceive(
        Origin calldata, /*_origin*/
        bytes32, /*_guid*/
        address, /*_to*/
        uint256, /*_amountLD*/
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) internal virtual {}

    function _debit(address from, uint256 amountLD, uint32 dstEid) internal virtual;

    function _credit(address to, uint256 amountLD, uint32 srcEid) internal virtual;
}
