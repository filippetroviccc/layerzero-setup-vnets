// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "../utils/Ownable.sol";

contract SimpleERC20 is Ownable {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public minter; // OFT contract as minter

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterUpdated(address indexed minter);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit MinterUpdated(_minter);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "ERC20: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    // Mint callable by the configured minter (OFT) for cross-chain mints
    function mint(address to, uint256 value) external {
        require(msg.sender == minter, "ERC20: not minter");
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    // Mint callable by the owner to bootstrap supply on a given chain
    function ownerMint(address to, uint256 value) external onlyOwner {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function burnFrom(address from, uint256 value) external {
        require(msg.sender == minter, "ERC20: not minter");
        uint256 bal = balanceOf[from];
        require(bal >= value, "ERC20: burn amount exceeds balance");
        balanceOf[from] = bal - value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "ERC20: transfer to zero");
        uint256 bal = balanceOf[from];
        require(bal >= value, "ERC20: transfer amount exceeds balance");
        balanceOf[from] = bal - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
