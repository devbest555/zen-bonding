// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

/// @title CustomTreasury Interface
interface ITreasury {
    function deposit(
        address _principleTokenAddress,
        uint256 _amountPrincipleToken,
        uint256 _amountPayoutToken
    ) external;

    function valueOfToken(address _principleTokenAddress, uint256 _amount) external view returns (uint256 value_);
}
