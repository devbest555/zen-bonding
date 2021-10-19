// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.7.5;

import "../types/Ownable.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";
import "../interfaces/IERC20.sol";

contract CustomTreasury is Ownable {
    
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    
    address public immutable PAYOUT_TOKEN;

    mapping(address => bool) public bondContract; 
    
    event BondContractToggled(address bondContract, bool approved);

    event Withdraw(address token, address destination, uint amount);
    
    constructor(address _payoutToken, address _initialOwner) {
        require(_payoutToken != address(0), "CustomTreasury: payoutToken must not be zero address");
        PAYOUT_TOKEN = _payoutToken;
        require(_initialOwner != address(0), "CustomTreasury: initialOwner must not be zero address");
        policy = _initialOwner;
    }

    /* ======== BOND CONTRACT FUNCTION ======== */

    /**
     *  @notice deposit principle token and recieve back payout token
     *  @param _principleTokenAddress address
     *  @param _amountPrincipleToken uint
     *  @param _amountPayoutToken uint
     */
    function deposit(address _principleTokenAddress, uint _amountPrincipleToken, uint _amountPayoutToken) external {
        require(bondContract[msg.sender], "msg.sender is not a bond contract");
        IERC20(_principleTokenAddress).safeTransferFrom(msg.sender, address(this), _amountPrincipleToken);
        IERC20(PAYOUT_TOKEN).safeTransfer(msg.sender, _amountPayoutToken);
    }

    /* ======== VIEW FUNCTION ======== */
    
    /**
    *   @notice returns payout token valuation of priciple
    *   @param _principleTokenAddress address
    *   @param _amount uint
    *   @return value_ uint
     */
    function valueOfToken(address _principleTokenAddress, uint _amount) public view returns ( uint value_ ) {
        // convert amount to match payout token decimals
        value_ = _amount.mul(10 ** IERC20(PAYOUT_TOKEN).decimals()).div(10 ** IERC20(_principleTokenAddress).decimals());
    }


    /* ======== POLICY FUNCTIONS ======== */

    /**
     *  @notice policy can withdraw ERC20 token to desired address
     *  @param _token uint
     *  @param _destination address
     *  @param _amount uint
     */
    function withdraw(address _token, address _destination, uint _amount) external onlyPolicy() {
        IERC20(_token).safeTransfer(_destination, _amount);

        emit Withdraw(_token, _destination, _amount);
    }

    /**
        @notice toggle bond contract
        @param _bondContract address
     */
    function toggleBondContract(address _bondContract) external onlyPolicy() {
        bondContract[_bondContract] = !bondContract[_bondContract];

        emit BondContractToggled(_bondContract, bondContract[_bondContract]);
    }
    
}
