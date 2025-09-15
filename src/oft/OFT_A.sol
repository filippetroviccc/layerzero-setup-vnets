// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "solidity-examples/contracts/token/oft/v2/ProxyOFTV2.sol";

contract OFT_A is ProxyOFTV2 {
    constructor(address token, uint8 sharedDecimals, address lzEndpoint)
        // Force a safe sharedDecimals (e.g., 6) to keep amountSD within uint64 bounds
        ProxyOFTV2(token, 6, lzEndpoint)
    {}
}
