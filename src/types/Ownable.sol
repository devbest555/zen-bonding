// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

import "hardhat/console.sol";

contract Ownable {
    address public policy;

    constructor() {
        policy = msg.sender;
    }

    modifier onlyPolicy() {
        require(msg.sender == policy, "Ownable: caller is not the owner");
        _;
    }

    function transferManagment(address _newOwner) external onlyPolicy {
        require(_newOwner != address(0), "Ownable: newOwner must not be zero address");
        policy = _newOwner;
    }
}
