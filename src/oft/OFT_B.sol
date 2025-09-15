// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "solidity-examples/contracts/token/oft/v2/OFTV2.sol";

contract OFT_B is OFTV2 {
    constructor(string memory name_, string memory symbol_, uint8 sharedDecimals, address lzEndpoint)
        // Force a safe sharedDecimals (e.g., 6) to keep amountSD within uint64 bounds
        OFTV2(name_, symbol_, 6, lzEndpoint)
    {}
}
