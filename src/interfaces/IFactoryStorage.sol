// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.7.5;

interface IFactoryStorage {
    function pushBond(
        address _payoutToken, 
        address _principleToken, 
        address _customTreasury, 
        address _customBond, 
        address _initialOwner, 
        uint[] calldata _tierCeilings, 
        uint[] calldata _fees
    ) external returns(address _treasury, address _bond);
}