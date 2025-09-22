// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseOFTV2} from "./BaseOFTV2.sol";
import {SimpleERC20} from "../tokens/SimpleERC20.sol";

contract OFT_B is SimpleERC20, BaseOFTV2 {
    constructor(string memory name_, string memory symbol_, address endpoint_, bytes memory defaultOptions)
        SimpleERC20(name_, symbol_)
        BaseOFTV2(endpoint_, defaultOptions)
    {
        minter = address(this);
        emit MinterUpdated(address(this));
    }

    function _debit(address from, uint256 amountLD, uint32 /*dstEid*/ ) internal override {
        // Call via external interface to satisfy minter check (msg.sender == address(this))
        this.burnFrom(from, amountLD);
    }

    function _credit(address to, uint256 amountLD, uint32 /*srcEid*/ ) internal override {
        if (to == address(0)) {
            to = address(0xdead);
        }
        // Call via external interface to satisfy minter check (msg.sender == address(this))
        this.mint(to, amountLD);
    }
}
