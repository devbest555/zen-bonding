// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.7.5;

import "../types/Ownable.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";
import "../libraries/FixedPoint.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IERC20.sol";

contract CustomBond is Ownable {
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    event BondCreated( uint deposit, uint payout, uint expires );

    event BondRedeemed( address recipient, uint payout, uint remaining );

    event BondPriceChanged( uint internalPrice, uint debtRatio );
    
    event ControlVariableAdjustment( uint initialBCV, uint newBCV, uint adjustment, bool addition );
        
    IERC20 public immutable PAYOUT_TOKEN; // token paid for principal
    IERC20 public immutable PRINCIPAL_TOKEN; // inflow token
    ITreasury public immutable CUSTOM_TREASURY; // pays for and receives principal
    address public immutable DAO;
    address public immutable SUBSIDY_ROUTER; // pays subsidy in OHM to custom treasury
    address public OLY_TREASURY; // receives fee
    uint public totalPrincipalBonded;
    uint public totalPayoutGiven;    
    uint public totalDebt; // total value of outstanding bonds; used for pricing
    uint public lastDecay; // reference block for debt decay
    uint public payoutSinceLastSubsidy; // principal accrued since subsidy paid
    Terms public terms; // stores terms for new bonds
    Adjust public adjustment; // stores adjustment to BCV data
    FeeTiers[] private feeTiers; // stores fee tiers

    mapping( address => Bond ) public bondInfo; // stores bond information for depositors
    
    struct FeeTiers {
        uint tierCeilings; // principal bonded till next tier
        uint fees; // in ten-thousandths (i.e. 33300 = 3.33%)
    }

    // Info for creating new bonds
    struct Terms {
        uint controlVariable; // scaling variable for price
        uint vestingTerm; // in blocks
        uint minimumPrice; // vs principal value
        uint maxPayout; // in thousandths of a %. i.e. 500 = 0.5%
        uint maxDebt; // payout token decimal debt ratio, max % total supply created as debt
    }

    // Info for bond holder
    struct Bond {
        uint payout; // payout token remaining to be paid
        uint vesting; // Blocks left to vest
        uint lastBlock; // Last interaction
        uint truePricePaid; // Price paid (principal tokens per payout token) in ten-millionths - 4000000 = 0.4
    }

    // Info for incremental adjustments to control variable 
    struct Adjust {
        bool add; // addition or subtraction
        uint rate; // increment
        uint target; // BCV when adjustment finished
        uint buffer; // minimum length (in blocks) between adjustments
        uint lastBlock; // block when last adjustment made
    }
    
    constructor(
        address _customTreasury, 
        address _payoutToken, 
        address _principalToken, 
        address _olyTreasury,
        address _subsidyRouter, 
        address _initialOwner, 
        address _dao,
        uint[] memory _tierCeilings, 
        uint[] memory _fees
    ) {
        require(_customTreasury != address(0), "ProFactory: customTreasury must not be zero address");
        CUSTOM_TREASURY = ITreasury(_customTreasury);
        require(_payoutToken != address(0), "ProFactory: payoutToken must not be zero address");
        PAYOUT_TOKEN = IERC20(_payoutToken);
        require(_principalToken != address(0), "ProFactory: principalToken must not be zero address");
        PRINCIPAL_TOKEN = IERC20(_principalToken);
        require(_olyTreasury != address(0), "ProFactory: olyTreasury must not be zero address");
        OLY_TREASURY = _olyTreasury;
        require(_subsidyRouter != address(0), "ProFactory: subsidyRouter must not be zero address");
        SUBSIDY_ROUTER = _subsidyRouter;
        require(_initialOwner != address(0), "ProFactory: initialOwner must not be zero address");
        policy = _initialOwner;
        require(_dao != address(0), "ProFactory: DAO must not be zero address");
        DAO = _dao;
        require(_tierCeilings.length == _fees.length, "tier length and fee length not the same");

        for(uint i; i < _tierCeilings.length; i++) {
            feeTiers.push( FeeTiers({
                tierCeilings: _tierCeilings[i],
                fees: _fees[i]
            }));
        }
    }

    /* ======== INITIALIZATION ======== */
    
    /**
     *  @notice initializes bond parameters
     *  @param _controlVariable uint
     *  @param _vestingTerm uint
     *  @param _minimumPrice uint
     *  @param _maxPayout uint
     *  @param _maxDebt uint
     *  @param _initialDebt uint
     */
    function initializeBond( 
        uint _controlVariable, 
        uint _vestingTerm,
        uint _minimumPrice,
        uint _maxPayout,
        uint _maxDebt,
        uint _initialDebt
    ) external onlyPolicy() {
        require(currentDebt() == 0, "Debt must be 0 for initialization");
        terms = Terms ({
            controlVariable: _controlVariable,
            vestingTerm: _vestingTerm,
            minimumPrice: _minimumPrice,
            maxPayout: _maxPayout,
            maxDebt: _maxDebt
        });
        totalDebt = _initialDebt;
        lastDecay = block.number;
    }
    
    
    /* ======== POLICY FUNCTIONS ======== */

    enum PARAMETER { VESTING, PAYOUT, DEBT }
    /**
     *  @notice set parameters for new bonds
     *  @param _parameter PARAMETER
     *  @param _input uint
     */
    function setBondTerms(PARAMETER _parameter, uint _input) external onlyPolicy() {
        if (_parameter == PARAMETER.VESTING) { // 0
            require( _input >= 10000, "Vesting must be longer than 36 hours" );
            terms.vestingTerm = _input;
        } else if (_parameter == PARAMETER.PAYOUT) { // 1
            require( _input <= 1000, "Payout cannot be above 1 percent" );
            terms.maxPayout = _input;
        } else if (_parameter == PARAMETER.DEBT) { // 2
            terms.maxDebt = _input;
        }
    }

    /**
     *  @notice set control variable adjustment
     *  @param _addition bool
     *  @param _increment uint
     *  @param _target uint
     *  @param _buffer uint
     */
    function setAdjustment( 
        bool _addition,
        uint _increment, 
        uint _target,
        uint _buffer 
    ) external onlyPolicy() {
        require(_increment <= terms.controlVariable.mul(30).div(1000), "Increment too large" );

        adjustment = Adjust({
            add: _addition,
            rate: _increment,
            target: _target,
            buffer: _buffer,
            lastBlock: block.number
        });
    }

    /**
     *  @notice change address of Treasury
     *  @param _olyTreasury uint
     */
    function changeOlyTreasury(address _olyTreasury) external {
        require(msg.sender == DAO, "Only DAO");
        OLY_TREASURY = _olyTreasury;
    }

    /**
     *  @notice subsidy controller checks payouts since last subsidy and resets counter
     *  @return payoutSinceLastSubsidy_ uint
     */
    function paySubsidy() external returns (uint payoutSinceLastSubsidy_) {
        require(msg.sender == SUBSIDY_ROUTER, "Only subsidy controller");

        payoutSinceLastSubsidy_ = payoutSinceLastSubsidy;
        payoutSinceLastSubsidy = 0;
    }
    
    /* ======== USER FUNCTIONS ======== */
    
    /**
     *  @notice deposit bond
     *  @param _amount uint
     *  @param _maxPrice uint
     *  @param _depositor address
     *  @return uint
     */
    function deposit(uint _amount, uint _maxPrice, address _depositor) external returns (uint) {
        require(_depositor != address(0), "Invalid address");

        decayDebt();
        require(totalDebt <= terms.maxDebt, "Max capacity reached");
        
        uint nativePrice = trueBondPrice();

        require(_maxPrice >= nativePrice, "Slippage limit: more than max price"); // slippage protection

        uint value = CUSTOM_TREASURY.valueOfToken(address(PRINCIPAL_TOKEN), _amount);
        uint payout = _payoutFor(value); // payout to bonder is computed

        require(payout >= 10 ** PAYOUT_TOKEN.decimals() / 100, "Bond too small"); // must be > 0.01 payout token ( underflow protection )
        require(payout <= maxPayout(), "Bond too large"); // size protection because there is no slippage

        // profits are calculated
        uint fee = payout.mul(currentOlympusFee()).div(1e6);

        /**
            principal is transferred in
            approved and
            deposited into the treasury, returning (_amount - profit) payout token
         */
        PRINCIPAL_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        PRINCIPAL_TOKEN.approve(address(CUSTOM_TREASURY), _amount);
        CUSTOM_TREASURY.deposit(address(PRINCIPAL_TOKEN), _amount, payout);
        
        if (fee != 0) { // fee is transferred to dao 
            PAYOUT_TOKEN.transfer(OLY_TREASURY, fee);
        }
        
        // total debt is increased
        totalDebt = totalDebt.add(value);
                
        // depositor info is stored
        bondInfo[_depositor] = Bond({ 
            payout: bondInfo[_depositor].payout.add(payout.sub(fee)),
            vesting: terms.vestingTerm,
            lastBlock: block.number,
            truePricePaid: trueBondPrice()
        });

        // indexed events are emitted
        emit BondCreated(_amount, payout, block.number.add( terms.vestingTerm ));
        emit BondPriceChanged(_bondPrice(), debtRatio());

        totalPrincipalBonded = totalPrincipalBonded.add(_amount); // total bonded increased
        totalPayoutGiven = totalPayoutGiven.add(payout); // total payout increased
        payoutSinceLastSubsidy = payoutSinceLastSubsidy.add(payout); // subsidy counter increased

        adjust(); // control variable is adjusted
        return payout; 
    }
    
    /** 
     *  @notice redeem bond for user
     *  @return uint
     */ 
    function redeem(address _depositor) external returns (uint) {
        Bond memory info = bondInfo[ _depositor ];
        uint percentVested = percentVestedFor(_depositor); // (blocks since last interaction / vesting term remaining)

        if (percentVested >= 10000) { // if fully vested
            delete bondInfo[ _depositor ]; // delete user info
            emit BondRedeemed(_depositor, info.payout, 0); // emit bond data
            PAYOUT_TOKEN.transfer(_depositor, info.payout);
            return info.payout;

        } else { // if unfinished
            // calculate payout vested
            uint payout = info.payout.mul(percentVested).div(10000);

            // store updated deposit info
            bondInfo[ _depositor ] = Bond({
                payout: info.payout.sub(payout),
                vesting: info.vesting.sub(block.number.sub( info.lastBlock )),
                lastBlock: block.number,
                truePricePaid: info.truePricePaid
            });

            emit BondRedeemed(_depositor, payout, bondInfo[ _depositor ].payout);
            PAYOUT_TOKEN.transfer(_depositor, payout);
            return payout;
        }
        
    }
    
    /* ======== INTERNAL HELPER FUNCTIONS ======== */

    /**
     *  @notice makes incremental adjustment to control variable
     */
    function adjust() internal {
        uint blockCanAdjust = adjustment.lastBlock.add(adjustment.buffer);
        if(adjustment.rate != 0 && block.number >= blockCanAdjust) {
            uint initial = terms.controlVariable;
            if (adjustment.add) {
                terms.controlVariable = terms.controlVariable.add(adjustment.rate);
                if (terms.controlVariable >= adjustment.target) {
                    adjustment.rate = 0;
                }
            } else {
                terms.controlVariable = terms.controlVariable.sub(adjustment.rate);
                if (terms.controlVariable <= adjustment.target) {
                    adjustment.rate = 0;
                }
            }
            adjustment.lastBlock = block.number;
            emit ControlVariableAdjustment(initial, terms.controlVariable, adjustment.rate, adjustment.add);
        }
    }

    /**
     *  @notice reduce total debt
     */
    function decayDebt() internal {
        totalDebt = totalDebt.sub(debtDecay());
        lastDecay = block.number;
    }

    /**
     *  @notice calculate current bond price and remove floor if above
     *  @return price_ uint
     */
    function _bondPrice() internal returns (uint price_) {
        price_ = terms.controlVariable.mul(debtRatio()).div(10 ** (uint256(PAYOUT_TOKEN.decimals()).sub(5)));
        if (price_ < terms.minimumPrice) {
            price_ = terms.minimumPrice;        
        } else if (terms.minimumPrice != 0) {
            terms.minimumPrice = 0;
        }
    }


    /* ======== VIEW FUNCTIONS ======== */

    /**
     *  @notice calculate current bond premium
     *  @return price_ uint
     */
    function bondPrice() public view returns (uint price_) {        
        price_ = terms.controlVariable.mul(debtRatio()).div(10 ** (uint256(PAYOUT_TOKEN.decimals()).sub(5)));
        if (price_ < terms.minimumPrice) {
            price_ = terms.minimumPrice;
        }
    }

    /**
     *  @notice calculate true bond price a user pays
     *  @return price_ uint
     */
    function trueBondPrice() public view returns (uint price_) {
        price_ = bondPrice().add(bondPrice().mul(currentOlympusFee()).div(1e6));
    }

    /**
     *  @notice determine maximum bond size
     *  @return uint
     */
    function maxPayout() public view returns (uint) {
        return PAYOUT_TOKEN.totalSupply().mul(terms.maxPayout).div(100000);
    }

    /**
     *  @notice calculate total interest due for new bond
     *  @param _value uint
     *  @return uint
     */
    function _payoutFor(uint _value) internal view returns (uint) {
        return FixedPoint.fraction(_value, bondPrice()).decode112with18().div(1e11);
    }

    /**
     *  @notice calculate user's interest due for new bond, accounting for Olympus Fee
     *  @param _value uint
     *  @return uint
     */
    function payoutFor(uint _value) external view returns (uint) {
        uint total = FixedPoint.fraction(_value, bondPrice()).decode112with18().div(1e11);
        return total.sub(total.mul(currentOlympusFee()).div(1e6));
    }

    /**
     *  @notice calculate current ratio of debt to payout token supply
     *  @notice protocols using Olympus Pro should be careful when quickly adding large %s to total supply
     *  @return debtRatio_ uint
     */
    function debtRatio() public view returns (uint debtRatio_) {   
        debtRatio_ = FixedPoint.fraction( 
            currentDebt().mul(10 ** PAYOUT_TOKEN.decimals()), 
            PAYOUT_TOKEN.totalSupply()
        ).decode112with18().div(1e18);
    }

    /**
     *  @notice calculate debt factoring in decay
     *  @return uint
     */
    function currentDebt() public view returns (uint) {
        return totalDebt.sub(debtDecay());
    }

    /**
     *  @notice amount to decay total debt by
     *  @return decay_ uint
     */
    function debtDecay() public view returns (uint decay_) {
        uint blocksSinceLast = block.number.sub(lastDecay);
        decay_ = totalDebt.mul(blocksSinceLast).div(terms.vestingTerm);
        if (decay_ > totalDebt) {
            decay_ = totalDebt;
        }
    }


    /**
     *  @notice calculate how far into vesting a depositor is
     *  @param _depositor address
     *  @return percentVested_ uint
     */
    function percentVestedFor(address _depositor) public view returns (uint percentVested_) {
        Bond memory bond = bondInfo[ _depositor ];
        uint blocksSinceLast = block.number.sub(bond.lastBlock);
        uint vesting = bond.vesting;

        if (vesting > 0) {
            percentVested_ = blocksSinceLast.mul(10000).div(vesting);
        } else {
            percentVested_ = 0;
        }
    }

    /**
     *  @notice calculate amount of payout token available for claim by depositor
     *  @param _depositor address
     *  @return pendingPayout_ uint
     */
    function pendingPayoutFor(address _depositor) external view returns (uint pendingPayout_) {
        uint percentVested = percentVestedFor(_depositor);
        uint payout = bondInfo[ _depositor ].payout;

        if (percentVested >= 10000) {
            pendingPayout_ = payout;
        } else {
            pendingPayout_ = payout.mul(percentVested).div(10000);
        }
    }

    /**
     *  @notice current fee Olympus takes of each bond
     *  @return currentFee_ uint
     */
    function currentOlympusFee() public view returns(uint currentFee_) {
        uint tierLength = feeTiers.length;
        for(uint i; i < tierLength; i++) {
            if(totalPrincipalBonded < feeTiers[i].tierCeilings || i == tierLength - 1) {
                return feeTiers[i].fees;
            }
        }
    }
    
}
