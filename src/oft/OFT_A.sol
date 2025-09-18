// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseOFTV2} from "./BaseOFTV2.sol";
import {SimpleERC20} from "../tokens/SimpleERC20.sol";

contract OFT_A is BaseOFTV2 {
    SimpleERC20 public immutable token;

    constructor(address token_, address endpoint_, bytes memory defaultOptions)
        BaseOFTV2(endpoint_, defaultOptions)
    {
        token = SimpleERC20(token_);
    }

    function _debit(address from, uint256 amountLD, uint32 /*dstEid*/ ) internal override {
        require(token.transferFrom(from, address(this), amountLD), "OFT: transferFrom failed");
    }

    function _credit(address to, uint256 amountLD, uint32 /*srcEid*/ ) internal override {
        require(token.transfer(to, amountLD), "OFT: transfer failed");
    }
}
