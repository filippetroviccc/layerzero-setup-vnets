// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "./SimpleERC20.sol";

contract TokenB is SimpleERC20 {
    constructor() SimpleERC20("TokenB", "TKB") {}
}

