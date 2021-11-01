

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.5;

import "../types/Ownable.sol";
import "../libraries/SafeMath.sol";
import "./CustomBond.sol";
import "./CustomTreasury.sol";
import "../interfaces/IFactoryStorage.sol";

contract Factory is Ownable {    
    using SafeMath for uint256;

    address immutable public TREASURY;
    address immutable public FACTORY_STORAGE;
    address immutable public SUBSIDY_ROUTER;
    address immutable public DAO;
    address immutable public HELPER;
    
    uint256[] public tierCeilings; 
    uint256[] public fees;

    event BondCreation(address treasury, address bond, address _initialOwner);

    event FeesAndTierCeilings(uint256[] tierCeilings, uint256[] fees);

    constructor(
        address _treasury,
        address _factoryStorage,
        address _subsidyRouter,
        address _dao,
        address _helper
    ) {
        require(_treasury != address(0), "Factory: treasury must not be zero address");
        TREASURY = _treasury;
        require(_factoryStorage != address(0), "Factory: factoryStorage must not be zero address");
        FACTORY_STORAGE = _factoryStorage;
        require(_subsidyRouter != address(0), "Factory: subsidyRouter must not be zero address");
        SUBSIDY_ROUTER = _subsidyRouter;
        require(_dao != address(0), "Factory: dao must not be zero address");
        DAO = _dao;
        require(_helper != address(0), "Factory: helper must not be zero address");
        HELPER = _helper;
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
        address _initialOwner
    ) external returns (address _treasury, address _bond) {
        require(fees.length > 0, "createBondAndTreasury: fees must be setup");

        CustomTreasury customTreasury = new CustomTreasury(_payoutToken, _initialOwner);
        CustomBond customBond = new CustomBond(
            address(customTreasury), 
            _payoutToken, 
            _principleToken, 
            TREASURY, 
            SUBSIDY_ROUTER, 
            _initialOwner, 
            DAO, 
            HELPER,
            tierCeilings, 
            fees
        );

        emit BondCreation(address(customTreasury), address(customBond), _initialOwner);

        return IFactoryStorage(FACTORY_STORAGE).pushBond(
            _payoutToken, 
            _principleToken, 
            address(customTreasury), 
            address(customBond), 
            _initialOwner, 
            tierCeilings, 
            fees
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
        address _initialOwner
    ) external returns (address _treasury, address _bond) {
        require(fees.length > 0, "createBond: fees must be setup");

        CustomBond bond = new CustomBond(
            _customTreasury, 
            _payoutToken, 
            _principleToken, 
            _customTreasury, 
            SUBSIDY_ROUTER, 
            _initialOwner, 
            DAO, 
            HELPER,
            tierCeilings, 
            fees
        );

        emit BondCreation(_customTreasury, address(bond), _initialOwner);

        return
            IFactoryStorage(FACTORY_STORAGE).pushBond(
                _payoutToken,
                _principleToken,
                _customTreasury,
                address(bond),
                _initialOwner,
                tierCeilings,
                fees
            );
    }

    /**
     *  @notice set fee for creating bond
     *  @param _tierCeilings uint[]
     *  @param _fees uint[]
     */
    function setTiersAndFees(
        uint256[] calldata _tierCeilings, 
        uint256[] calldata _fees
    ) external onlyPolicy {
        require(_tierCeilings.length == _fees.length, "setTiersAndFees: tier length and fee length must be same");

        uint256 feeSum = 0;
        for (uint256 i; i < _fees.length; i++) {
            feeSum = feeSum.add(_fees[i]);
        }
        
        require(feeSum > 0, "setTiersAndFees: fee must greater than 0");

        for (uint256 i; i < _fees.length; i++) {
            tierCeilings.push(_tierCeilings[i]);
            fees.push(_fees[i]);
        }

        emit FeesAndTierCeilings(_tierCeilings, _fees);
    }
}
