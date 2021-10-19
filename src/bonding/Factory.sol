

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

import "../types/Ownable.sol";
import "./CustomBond.sol";
import "./CustomTreasury.sol";
import "../interfaces/IFactoryStorage.sol";

contract Factory is Ownable {
    
    address immutable public TREASURY;
    address immutable public FACTORY_STORAGE;
    address immutable public SUBSIDY_ROUTER;
    address immutable public DAO;
    
    constructor(
        address _treasury, 
        address _factoryStorage, 
        address _subsidyRouter, 
        address _dao
    ) {
        require(_treasury != address(0), "Factory: treasury must not be zero address");
        TREASURY = _treasury;
        require(_factoryStorage != address(0), "Factory: factoryStorage must not be zero address");
        FACTORY_STORAGE = _factoryStorage;
        require(_subsidyRouter != address(0), "Factory: subsidyRouter must not be zero address");
        SUBSIDY_ROUTER = _subsidyRouter;
        require(_dao != address(0), "Factory: dao must not be zero address");
        DAO = _dao;
    }
    
    /* ======== POLICY FUNCTIONS ======== */
    
    /**
        @notice deploys custom treasury and custom bond contracts and returns address of both
        @param _payoutToken address
        @param _principleToken address
        @param _initialOwner address
        @return _treasury address
        @return _bond address
     */
    function createBondAndTreasury(
        address _payoutToken, 
        address _principleToken, 
        address _initialOwner, 
        uint[] calldata _tierCeilings, 
        uint[] calldata _fees
    ) external onlyPolicy() returns(address _treasury, address _bond) {    
        CustomTreasury customTreasury = new CustomTreasury(_payoutToken, _initialOwner);
        CustomBond customBond = new CustomBond(
            address(customTreasury), 
            _payoutToken, 
            _principleToken, 
            TREASURY, 
            SUBSIDY_ROUTER, 
            _initialOwner, 
            DAO, 
            _tierCeilings, 
            _fees
        );
        
        return IFactoryStorage(FACTORY_STORAGE).pushBond(
            _payoutToken, 
            _principleToken, 
            address(customTreasury), 
            address(customBond), 
            _initialOwner, 
            _tierCeilings, 
            _fees
        );
    }

    /**
        @notice deploys custom treasury and custom bond contracts and returns address of both
        @param _payoutToken address
        @param _principleToken address
        @param _customTreasury address
        @param _initialOwner address
        @return _treasury address
        @return _bond address
     */
    function createBond(
        address _payoutToken, 
        address _principleToken, 
        address _customTreasury, 
        address _initialOwner, 
        uint[] calldata _tierCeilings, 
        uint[] calldata _fees 
    ) external onlyPolicy() returns(address _treasury, address _bond) {
        CustomBond bond = new CustomBond(
            _customTreasury, 
            _payoutToken, 
            _principleToken, 
            _customTreasury, 
            SUBSIDY_ROUTER, 
            _initialOwner, 
            DAO, 
            _tierCeilings, 
            _fees
        );

        return IFactoryStorage(FACTORY_STORAGE).pushBond(
            _payoutToken, 
            _principleToken,
            _customTreasury, 
            address(bond), 
            _initialOwner, 
            _tierCeilings, 
            _fees
        );
    }
    
}