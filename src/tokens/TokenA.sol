// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "./SimpleERC20.sol";

contract TokenA is SimpleERC20 {
    constructor() SimpleERC20("TokenA", "TKA") {}
}

