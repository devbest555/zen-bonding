// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

/// @notice Interface for Helper
interface IHelper {

    function swapForDeposit(
        bytes calldata _swapArgs
    ) external returns (address lpAddress_, uint256 lpAmount_);

}
