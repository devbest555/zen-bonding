// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.5;

import "../types/Ownable.sol";

contract FactoryStorage is Ownable {
    struct BondDetails {
        address _payoutToken;
        address _principleToken;
        address _treasuryAddress;
        address _bondAddress;
        address _initialOwner;
        uint256[] _tierCeilings;
        uint256[] _fees;
    }

    BondDetails[] public bondDetails;

    address public factory;

    mapping(address => uint256) public indexOfBond;

    event NewBond(address treasury, address bond, address _initialOwner);
    
    /* ======== POLICY FUNCTIONS ======== */

    /**
        @notice pushes bond details to array
        @param _payoutToken address
        @param _principleToken address
        @param _customTreasury address
        @param _customBond address
        @param _initialOwner address
        @param _tierCeilings uint[]
        @param _fees uint[]
        @return _treasury address
        @return _bond address
     */
    function pushBond(
        address _payoutToken, 
        address _principleToken, 
        address _customTreasury, 
        address _customBond, 
        address _initialOwner, 
        uint[] calldata _tierCeilings, 
        uint[] calldata _fees
    ) external returns(address _treasury, address _bond) {
        // require(factory == msg.sender, "Not Factory");

        indexOfBond[_customBond] = bondDetails.length;

        bondDetails.push(
            BondDetails({
                _payoutToken: _payoutToken,
                _principleToken: _principleToken,
                _treasuryAddress: _customTreasury,
                _bondAddress: _customBond,
                _initialOwner: _initialOwner,
                _tierCeilings: _tierCeilings,
                _fees: _fees
            })
        );

        emit NewBond(_customTreasury, _customBond, _initialOwner);
        
        return(_customTreasury, _customBond);
    }

    /**
        @notice changes flux pro factory address
        @param _factory address
     */
    function setFactoryAddress(address _factory) external onlyPolicy {
        factory = _factory;
    }
}
