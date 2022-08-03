// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import '../interfaces/IPlearnRouter02.sol';
import '../interfaces/IPlearnFeeHandler.sol';
import "@plearn-libs/plearn-swap-core/contracts/interfaces/IPlearnPair.sol";

contract PlearnFeeManager is Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _pairs;

    event NewPlearnRouter(address indexed sender, address indexed router);
    event NewSlippageTolerance(address indexed sender, uint slippageTolerance);
    event NewMinimumPlearn(address indexed sender, uint minimumPlearn);
    event NewPlearnFeeHandlerAddress(address indexed sender, address indexed feeHandlerAddress);
    event NewPlearnTeamAddress(address indexed sender, address indexed teamAddress);
    event NewPlearnBurnRate(address indexed sender, uint plearnBurnRate);
    event AdminTokenRecovery(address tokenRecovered, uint256 amount);

    IERC20 public plearn;
    IPlearnRouter02 public plearnRouter;
    IPlearnFeeHandler public plearnFeeHandler;
    address public plearnTeamAddress;

    uint public plearnBurnRate; // rate for burn (e.g. 200 = 2%, 150 = 1.50%)
    uint constant public RATE_DENOMINATOR = 10000;
    uint public slippageTolerance;
    uint constant public SLIPPAGE_DENOMINATOR = 10000;
    uint public minimumPlearn;

    // The precision factor
    uint256 public PRECISION_FACTOR = 1000000000000;

    constructor(
        IERC20 _plearn,
        IPlearnFeeHandler _plearnFeeHandler,
        IPlearnRouter02 _plearnRouter,
        address _plearnTeamAddress,
        uint _plearnBurnRate,
        uint _slippageTolerance,
        uint _minimumPlearn
    ) {
        plearn = _plearn;
        plearnFeeHandler = _plearnFeeHandler;
        plearnRouter = _plearnRouter;
        plearnTeamAddress = _plearnTeamAddress;
        plearnBurnRate = _plearnBurnRate;
        slippageTolerance = _slippageTolerance;
        minimumPlearn = _minimumPlearn;
    }

    /**
     * @notice Sell all LP token from _pairs, buy back $PLN.
     * @dev Callable by owner
     */
    function processAllFee(bool ignoreError) external onlyOwner {
        IPlearnPair[] memory pairs = getPairsForProcessFee();
        IPlearnFeeHandler.RemoveLiquidityInfo[] memory liquidityList = new IPlearnFeeHandler.RemoveLiquidityInfo[](pairs.length);
        IPlearnFeeHandler.SwapInfo[] memory swapList = new IPlearnFeeHandler.SwapInfo[](pairs.length);

        for (uint256 i = 0; i < pairs.length; i++) {
            IPlearnPair pair =  pairs[i];
            sendLP(pair);

            uint lpBurnAmount = pair.balanceOf(address(plearnFeeHandler));
            (uint amountAMin, uint amountBMin) = getLiquidityTokenMinAmount(pair, lpBurnAmount);
            
            liquidityList[i] = IPlearnFeeHandler.RemoveLiquidityInfo({
                pair: pair,
                amount: lpBurnAmount,
                amountAMin: amountAMin,
                amountBMin: amountBMin
            });
        }

        plearnFeeHandler.processFee(liquidityList, new IPlearnFeeHandler.SwapInfo[](0), ignoreError);

        for (uint256 i = 0; i < pairs.length; i++) {            
            IPlearnPair pair =  pairs[i];
            swapList[i] = getSwapInfo(pair);
        }
        plearnFeeHandler.processFee(new IPlearnFeeHandler.RemoveLiquidityInfo[](0), swapList, ignoreError);

        uint plearnAmount = plearn.balanceOf(address(plearnFeeHandler));
        plearnFeeHandler.sendPlearn(plearnAmount);
    }

    /**
     * @notice Send LP tokens to specified wallets(fee handler and team)
     * @dev Callable by owner
     */
    function sendLP(IPlearnPair pair) public onlyOwner {
        uint lpAmount = pair.balanceOf(address(msg.sender));
        require (lpAmount > 0, "invalid amount");
        uint burnAmount = lpAmount * plearnBurnRate / RATE_DENOMINATOR;
        // The rest goes to the team wallet.
        uint teamAmount = lpAmount - burnAmount;
        IERC20(address(pair)).safeTransferFrom(address(msg.sender), address(plearnFeeHandler), burnAmount);
        IERC20(address(pair)).safeTransferFrom(address(msg.sender), plearnTeamAddress, teamAmount);
    }


    /**
     * @notice It allows the owner to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by owner.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }


    /**
     * @notice Set address for `plearn fee handler`
     * @dev Callable by owner
     */
    function setPlearnFeeHandlerAddress(address _plearnFeeHandler) external onlyOwner {
        plearnFeeHandler = IPlearnFeeHandler(_plearnFeeHandler);
        emit NewPlearnFeeHandlerAddress(msg.sender, _plearnFeeHandler);
    }

    /**
     * @notice Set team address
     * @dev Callable by owner
     */
    function setPlearnTeamAddress(address _plearnTeamAddress) external onlyOwner {
        plearnTeamAddress = _plearnTeamAddress;
        emit NewPlearnTeamAddress(msg.sender, _plearnTeamAddress);
    }

    /**
     * @notice Set percentage of $PLN being sent for burn
     * @dev Callable by owner
     */
    function setPlearnBurnRate(uint _plearnBurnRate) external onlyOwner {
        require(_plearnBurnRate < RATE_DENOMINATOR, "invalid rate");
        plearnBurnRate = _plearnBurnRate;
        emit NewPlearnBurnRate(msg.sender, _plearnBurnRate);
    }

    /**
     * @notice Set slippage tolerance for swaps & liquidity
     * @dev Callable by owner
     */
    function setSlippageTolerance(uint _slippageTolerance) external onlyOwner {
        require(_slippageTolerance < SLIPPAGE_DENOMINATOR, "invalid slippage");
        slippageTolerance = _slippageTolerance;
        emit NewSlippageTolerance(msg.sender, _slippageTolerance);
    }

    /**
     * @notice Set minimum plearn for remove liquidity
     * @dev Callable by owner
     */
    function setMinimumPlearn(uint _amount) external onlyOwner {
        minimumPlearn = _amount;
        emit NewMinimumPlearn(msg.sender, _amount);
    }

    /**
     * @notice Set PlearnRouter
     * @dev Callable by owner
     */
    function setPlearnRouter(address _plearnRouter) external onlyOwner {
        plearnRouter = IPlearnRouter02(_plearnRouter);
        emit NewPlearnRouter(msg.sender, _plearnRouter);
    }

    function addPair(address _address) external onlyOwner {
        EnumerableSet.add(_pairs, _address);
    }

    function removePair(address _address) external onlyOwner {
        EnumerableSet.remove(_pairs, _address);
    }

    function getPairCount() public view returns (uint256) {
        return EnumerableSet.length(_pairs);
    }

    function containsPair(address _address) public view returns (bool) {
        return EnumerableSet.contains(_pairs, _address);
    }

    function getPairsForProcessFee() public view returns (IPlearnPair[] memory pairs) {
        uint pairCount = getPairCount();
        IPlearnPair[] memory validPairs = new IPlearnPair[](pairCount);
        uint counter = 0;

        for (uint256 i = 0; i < pairCount; i++) {
            address pairAddress = EnumerableSet.at(_pairs, i);
            IPlearnPair pair = IPlearnPair(pairAddress);
            uint lpBalance = pair.balanceOf(address(msg.sender));
            uint lpBurnAmount = lpBalance * plearnBurnRate / RATE_DENOMINATOR;
            if (lpBurnAmount > 0) {
                (uint amountAMin, uint amountBMin) = getLiquidityTokenMinAmount(pair, lpBurnAmount);
                uint plearnAmountOutMin = pair.token0() == address(plearn) ? amountAMin : amountBMin;
                if (plearnAmountOutMin >= minimumPlearn) {
                    validPairs[counter++] = pair;
                }
            }
        }        
        
        pairs = new IPlearnPair[](counter);
        for (uint256 i = 0; i < counter; i++) {
            pairs[i] = validPairs[i];
        }        
    }

    function getLiquidityTokenMinAmount(IPlearnPair pair, uint lpBurnAmount) public view returns (uint _amountAMin, uint _amountBMin) {
        uint totalSupply = pair.totalSupply();
        (uint reserve0, uint reserve1, ) = pair.getReserves();
       
        uint tokenAAmount = (((reserve0 * PRECISION_FACTOR) / totalSupply) * lpBurnAmount) / PRECISION_FACTOR;
        uint tokenASlippageAmount = tokenAAmount * slippageTolerance / SLIPPAGE_DENOMINATOR;
        _amountAMin = tokenAAmount - tokenASlippageAmount;
        

        uint tokenBAmount = (((reserve1 * PRECISION_FACTOR) / totalSupply) * lpBurnAmount) / PRECISION_FACTOR;
        uint tokenBSlippageAmount = tokenBAmount * slippageTolerance / SLIPPAGE_DENOMINATOR;
        _amountBMin = tokenBAmount - tokenBSlippageAmount;
    }
    
    function getSwapInfo(IPlearnPair pair) public view returns (IPlearnFeeHandler.SwapInfo memory _swapInfo) {
        address token0 = pair.token0();
        address token1 = pair.token1();
        require(token0 == address(plearn) || token1 == address(plearn) , "invalid pair");
        
        address tokenIn = token0 == address(plearn) ? address(token1) : address(token0);
        address tokenOut = address(plearn);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint amountIn = IERC20(tokenIn).balanceOf(address(plearnFeeHandler));
        uint[] memory swapAmountOut = plearnRouter.getAmountsOut(amountIn, path);
        uint swapSlippageAmount = swapAmountOut[1] * slippageTolerance / SLIPPAGE_DENOMINATOR;
        uint amountOutMin = swapAmountOut[1] - swapSlippageAmount;
        
        _swapInfo = IPlearnFeeHandler.SwapInfo({
                amountIn: amountIn,
                amountOutMin: amountOutMin,
                path: path
            });
    }

}