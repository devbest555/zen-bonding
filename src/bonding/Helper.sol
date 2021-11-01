

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.5;

import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";
import "../interfaces/IUniswapV2Router2.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IHelper.sol";
import "hardhat/console.sol";

contract Helper is IHelper {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address private immutable UNISWAP2_FACTORY;
    address private immutable UNISWAP2_ROUTER;
    address private immutable SUSHI_FACTORY;
    address private immutable SUSHI_ROUTER;
    address private immutable WETH;
    IERC20 private constant ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Provides a standard implementation for transferring assets between
    /// the msg.sender and the helper, by wrapping the action.
    modifier transferHandler(bytes memory _encodedArgs) {            
        (
            uint256 depositAmount,
            address depositAsset,
            address payoutAsset,
            address incomingAsset
        ) = __decodeSwapArgs(_encodedArgs);
        
        if(depositAsset != address(0)) {
            IERC20(depositAsset).safeTransferFrom(msg.sender, address(this), depositAmount);
        }

        // Execute call
        _;

        // remain asset to send caller back
        __transferAssetToCaller(msg.sender, depositAsset);
        __transferAssetToCaller(msg.sender, payoutAsset);
    }
    
    receive() external payable {}

    constructor(
        address _uniswap2Factory,
        address _uniswap2Router,
        address _sushiswapFactory,
        address _sushiswapRouter
    ) {
        require(_uniswap2Factory != address(0), "Helper: _uniswap2Factory must not be zero address");
        require(_uniswap2Router != address(0), "Helper: _uniswap2Router must not be zero address");
        require(_sushiswapFactory != address(0), "Helper: _sushiswapFactory must not be zero address");
        require(_sushiswapRouter != address(0), "Helper: _sushiswapRouter must not be zero address");

        UNISWAP2_FACTORY = _uniswap2Factory;
        UNISWAP2_ROUTER = _uniswap2Router;
        SUSHI_FACTORY = _sushiswapFactory;    
        SUSHI_ROUTER = _sushiswapRouter;  
        WETH = IUniswapV2Router2(_uniswap2Router).WETH();
    }

    /// @notice get LP token and LP amount
    /// @param _swapArgs encoded data
    /// @return lpAddress_ lp token address
    /// @return lpAmount_ lp token amount
    function swapForDeposit(bytes calldata _swapArgs)
        external        
        override        
        transferHandler(_swapArgs)
        returns (address lpAddress_, uint256 lpAmount_)
    {
        (lpAddress_, lpAmount_) = __swapForDeposit(_swapArgs);
    }

    /// Avoids stack-too-deep error.
    function __swapForDeposit(bytes calldata _swapArgs) private 
        returns (address lpAddress_, uint256 lpAmount_)
    {
        (
            uint256 depositAmount,
            address depositAsset,
            address payoutAsset,
            address incomingAsset
        ) = __decodeSwapArgs(_swapArgs);

        address router;
        address factory;
        uint256 payoutAmount = depositAmount;     
        address[] memory path = new address[](2);  
        if(depositAsset != payoutAsset) {             
            path[0] = depositAsset;            
            if(path[0] == address(0)) {
                path[0] = WETH;
            }
            path[1] = payoutAsset;

            (router,) = __checkPool(path);
            
            require(router != address(0), "Swap: No Pool");

            // Get payoutAmount from depositAsset on Uniswap/Sushiswap
            payoutAmount = IUniswapV2Router2(router).getAmountsOut(depositAmount, path)[1];
            
            if(path[0] == WETH) {
                __swapETHToToken(depositAmount, payoutAmount, router, path);
            } else {
                __swapTokenToToken(depositAmount, payoutAmount, router, path);
            }
        }   
        
        path[0] = payoutAsset;
        path[1] = incomingAsset;

        (router, factory) = __checkPool(path);
        
        require(router != address(0), "Swap: No Pool");

        uint256 expectedAmount = IUniswapV2Router2(router).getAmountsOut(payoutAmount.div(2), path)[1];

        __swapTokenToToken(payoutAmount.div(2), expectedAmount, router, path);
        
        (lpAddress_, lpAmount_) = addLiquidityToken(
            factory,
            router,
            path,
            payoutAmount,
            expectedAmount
        );              
    }

    /// @notice Swap ERC20 Token to ERC20 Token
    function __swapTokenToToken(
        uint256 _payoutAmount,
        uint256 _expectedAmount,
        address _router,
        address[] memory _path
    ) private returns (uint256[] memory amounts_) {
        __approveMaxAsNeeded(_path[0], _router, _payoutAmount);
        
        amounts_ = IUniswapV2Router2(_router).swapExactTokensForTokens(
            _payoutAmount,
            _expectedAmount,
            _path,
            address(this),
            block.timestamp.add(1)
        );
    }

    /// @notice Swap ETH to ERC20 Token
    function __swapETHToToken(
        uint256 _payoutAmount,
        uint256 _expectedAmount,
        address _router,
        address[] memory _path
    ) public payable returns (uint256[] memory amounts_) {
        __approveMaxAsNeeded(_path[0], _router, _payoutAmount);

        amounts_ = IUniswapV2Router2(_router).swapExactETHForTokens{value: address(this).balance}(
            _expectedAmount,
            _path,
            address(this),
            block.timestamp.add(1)
        );
    }

    /// @notice get LP token on uniswap/sushiswap
    /// @param _factory factory address of uni/sushi
    /// @param _router router address of uni/sushi
    /// @param _path address[]
    /// @param _amountADesired tokenA amount
    /// @param _amountBDesired tokenB amount
    /// @return lpAddress_ lp token address
    /// @return lpAmount_ lp token amount
    function addLiquidityToken(
        address _factory,
        address _router,
        address[] memory _path,
        uint256 _amountADesired,
        uint256 _amountBDesired        
    )
        private  
        returns (address lpAddress_, uint256 lpAmount_)
    {
        if(_path[0] == address(ETH_ADDRESS) || _path[0] == WETH) {
            lpAmount_ = __addETHAndToken(
                _router,
                _path,
                _amountADesired,
                _amountBDesired
            );
        } else {
            lpAmount_ = __addTokenAndToken(
                _router,
                _path,
                _amountADesired,
                _amountBDesired
            ); 
        }
               

        lpAddress_ = IUniswapV2Factory(_factory).getPair(_path[0], _path[1]);

        __transferAssetToCaller(msg.sender, lpAddress_);        
    }

    /// @notice addLiquidityETH for lp tokens on uni/sushi
    function __addETHAndToken(
        address _router,
        address[] memory _path,
        uint256 _amountADesired,
        uint256 _amountBDesired
    ) public payable returns (uint256 lpAmount_) {
        __approveMaxAsNeeded(_path[0], _router, _amountADesired);
        __approveMaxAsNeeded(_path[1], _router, _amountBDesired);

        payable(address(_router)).transfer(_amountADesired);

        // Execute addLiquidityETH on Uniswap/Sushi
        (, , lpAmount_) = IUniswapV2Router2(_router).addLiquidityETH{value: address(this).balance}(
            _path[1],
            _amountBDesired,
            1,
            1,
            msg.sender,
            block.timestamp.add(1)
        );
    }

    /// @notice addLiquidity for lp tokens on Uniswap/Sushi
    /// @dev Avoid stack too deep
    function __addTokenAndToken(
        address _router,
        address[] memory _path,
        uint256 _amountADesired,
        uint256 _amountBDesired
    ) private returns (uint256 lpAmount_) {
        __approveMaxAsNeeded(_path[0], _router, _amountADesired);
        __approveMaxAsNeeded(_path[1], _router, _amountBDesired);
        
        // Get expected output amount on Uniswap/Sushi
        address[] memory path = new address[](2);
        path[0] = _path[1];
        path[1] = _path[0];
        uint256 amountAMax = IUniswapV2Router2(_router).getAmountsOut(_amountBDesired, path)[1];
        
        // Execute addLiquicity on Uniswap/Sushi
        (, , lpAmount_) = IUniswapV2Router2(_router).addLiquidity(
            _path[0],
            _path[1],
            amountAMax,
            _amountBDesired,
            1,
            1,
            msg.sender,
            block.timestamp.add(1)
        );
    }

    /// @dev Helper to decode swap encoded call arguments
    function __decodeSwapArgs(bytes memory _encodedCallArgs)
        private
        pure
        returns (
            uint256 depositAmount_,
            address depositAsset_,
            address payoutAsset_,
            address incomingAsset_
        )
    {
        return abi.decode(_encodedCallArgs, (uint256, address, address, address));
    }

    /// @dev Helper for asset to approve their max amount of an asset.
    function __approveMaxAsNeeded(
        address _asset,
        address _target,
        uint256 _neededAmount
    ) private {
        if (IERC20(_asset).allowance(address(this), _target) < _neededAmount) {
            IERC20(_asset).safeApprove(_target, type(uint256).max);
        }
    }

    /// @dev Helper to transfer full contract balances of assets to the caller
    function __transferAssetToCaller(address payable _target, address _asset) private {
        uint256 transferAmount;
        if(_asset == address(ETH_ADDRESS) || _asset == address(0)) {
            transferAmount = address(this).balance;
            if (transferAmount > 0) {
                _target.transfer(transferAmount);
            }
        } else {
            transferAmount = IERC20(_asset).balanceOf(address(this));
            if (transferAmount > 0) {
                IERC20(_asset).safeTransfer(_target, transferAmount);
            }
        }        
    }

    /// @dev check if special pool exist on uniswap or sushiswap
    function __checkPool(address[] memory _path) private view returns (address router_, address factory_) {        
        address uniPool = IUniswapV2Factory(UNISWAP2_FACTORY).getPair(_path[0], _path[1]);   
        address sushiPool = IUniswapV2Factory(SUSHI_FACTORY).getPair(_path[0], _path[1]);
        
        if(uniPool == address(0) && sushiPool != address(0)) {
            return (SUSHI_ROUTER, SUSHI_FACTORY);
        } else if(uniPool != address(0) && sushiPool == address(0)) {
            return (UNISWAP2_ROUTER, UNISWAP2_FACTORY);
        } else if(uniPool != address(0) && sushiPool != address(0)) {
            return (UNISWAP2_ROUTER, UNISWAP2_FACTORY);
        } else if(uniPool == address(0) && sushiPool == address(0)) {
            return (address(0), address(0));
        }
    }

    /// @notice Gets the `UNISWAP2_FACTORY` variable
    function getUniswapFactory() external view returns (address factory_) {
        return UNISWAP2_FACTORY;
    }

    /// @notice Gets the `SUSHI_FACTORY` variable
    function getSushiFactory() external view returns (address factory_) {
        return SUSHI_FACTORY;
    }

    /// @notice Gets the `UNISWAP2_ROUTER` variable
    function getUniswapRouter() external view returns (address router_) {
        return UNISWAP2_ROUTER;
    }

    /// @notice Gets the `SUSHI_ROUTER` variable
    function getSushiRouter() external view returns (address router_) {
        return SUSHI_ROUTER;
    }
}
