// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import './interfaces/IWETH.sol';
import './interfaces/IPlearnRouter02.sol';
import "@plearn-libs/plearn-swap-core/contracts/interfaces/IPlearnPair.sol";
import "@plearn-libs/plearn-swap-core/contracts/interfaces/IPlearnFactory.sol";

contract PlearnFeeHandlerV2 is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct RemoveLiquidityInfo {
        IPlearnPair pair;
        uint amount;
        uint amountAMin;
        uint amountBMin;
    }

    struct SwapInfo {
        address[] path;
    }

    struct LPData {
        address lpAddress;
        address token0;
        uint256 token0Amt;
        address token1;
        uint256 token1Amt;
        uint256 userBalance;
        uint256 totalSupply;
    }

    event SwapFailure(uint amountIn, uint amountOutMin, address[] path);
    event RmoveLiquidityFailure(IPlearnPair pair, uint amount, uint amountAMin, uint amountBMin);
    event NewPlearnRouter(address indexed sender, address indexed router);
    event NewOperatorAddress(address indexed sender, address indexed operator);
    event NewPlearnBurnAddress(address indexed sender, address indexed burnAddress);
    event NewPlearnTeamAddress(address indexed sender, address indexed teamAddress);
    event NewPlearnBurnRate(address indexed sender, uint plearnBurnRate);
    event NewSlippageTolerance(address indexed sender, uint slippageTolerance);

    address public plearn;
    IPlearnRouter02 public plearnRouter;
    address public operatorAddress; // address of the operator
    address public plearnBurnAddress;
    address public plearnTeamAddress;
    uint public plearnBurnRate; // rate for burn (e.g. 200 = 2%, 150 = 1.50%)
    uint constant public RATE_DENOMINATOR = 10000;
    uint public slippageTolerance;
    uint constant public SLIPPAGE_DENOMINATOR = 10000;
    uint constant UNLIMITED_APPROVAL_AMOUNT = type(uint256).max;
    mapping(address => bool) public validDestination;
    IWETH WETH;

    // Maximum amount of BNB to top-up operator
    uint public operatorTopUpLimit;

    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner() || msg.sender == operatorAddress, "Not owner/operator");
        _;
    }

    function initialize(
        address _plearn,
        address _plearnRouter,
        address _operatorAddress,
        address _plearnBurnAddress,
        address _plearnTeamAddress,
        uint _plearnBurnRate,
        uint _slippageTolerance,
        address[] memory destinations
    )
        external
        initializer
    {
        __Ownable_init();
        __UUPSUpgradeable_init();
        plearn = _plearn;
        plearnRouter = IPlearnRouter02(_plearnRouter);
        operatorAddress = _operatorAddress;
        plearnBurnAddress = _plearnBurnAddress;
        plearnTeamAddress = _plearnTeamAddress;
        plearnBurnRate = _plearnBurnRate;
        slippageTolerance = _slippageTolerance;
        for (uint256 i = 0; i < destinations.length; ++i)
        {
            validDestination[destinations[i]] = true;
        }
        WETH = IWETH(plearnRouter.WETH());
        operatorTopUpLimit = 1 ether;
    }

    /**
     * @notice Sell LP token, buy back $PLN. The amount can be specified by the caller.
     * @dev Callable by owner/operator
     */
    function processFee(
        address[] memory pairs,
        SwapInfo[] calldata swapList,
        bool ignoreError
    )
        external
        onlyOwnerOrOperator
    {

        for (uint256 i = 0; i < pairs.length; ++i) {
            address pairAddress = pairs[i];
            IPlearnPair pair = IPlearnPair(pairAddress);
            (uint token0Amt, uint token1Amt, ) = pair.getReserves();
            uint lpBalance = pair.balanceOf(address(this));
            uint totalSupply = pair.totalSupply();
            (uint amountAMin, uint amountBMin) = _getTokenAmountMinFromLiquidity(token0Amt, token1Amt, lpBalance, totalSupply);
            
            removeLiquidity(
                RemoveLiquidityInfo({
                    pair: pair,
                    amount: lpBalance,
                    amountAMin: amountAMin,
                    amountBMin: amountBMin
            }), ignoreError);
        }

        for (uint256 i = 0; i < swapList.length; ++i) {
            address[] memory path = swapList[i].path;
            address token = path[0];
            uint amountIn = IERC20Upgradeable(token).balanceOf(address(this));
            uint[] memory swapAmountOut = plearnRouter.getAmountsOut(
                amountIn,
                path
            );
            uint swapSlippageAmount = swapAmountOut[1] * slippageTolerance / SLIPPAGE_DENOMINATOR;
            uint amountOutMin = swapAmountOut[1] - swapSlippageAmount;
        
            swap(amountIn, amountOutMin, path, ignoreError);
        }
    }

    function removeLiquidity(
        RemoveLiquidityInfo memory info,
        bool ignoreError
    )
        internal
    {
        uint allowance = info.pair.allowance(address(this), address(plearnRouter));
        if (allowance < info.amount) {
            IERC20Upgradeable(address(info.pair)).safeApprove(address(plearnRouter), UNLIMITED_APPROVAL_AMOUNT);
        }
        address token0 = info.pair.token0();
        address token1 = info.pair.token1();
        try plearnRouter.removeLiquidity(
                token0,
                token1,
                info.amount,
                info.amountAMin,
                info.amountBMin,
                address(this),
                block.timestamp
            )
        {
            // do nothing here
        } catch {
            emit RmoveLiquidityFailure(info.pair, info.amount, info.amountAMin, info.amountBMin);
            require(ignoreError, "remove liquidity failed");
            // if one of the swap fails, we do NOT revert and carry on
        }
    }

    /**
     * @notice Swap tokens for $PLN
     */
    function swap(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        bool ignoreError
    )
        internal
    {
        require(path.length > 1, "invalid path");
        require(validDestination[path[path.length - 1]], "invalid path");
        address token = path[0];
        uint tokenBalance = IERC20Upgradeable(token).balanceOf(address(this));
        amountIn = (amountIn > tokenBalance) ? tokenBalance : amountIn;
        // TODO: need to adjust `token0AmountOutMin` ?
        uint allowance = IERC20Upgradeable(token).allowance(address(this), address(plearnRouter));
        if (allowance < amountIn) {
            IERC20Upgradeable(token).safeApprove(address(plearnRouter), UNLIMITED_APPROVAL_AMOUNT);
        }
        try plearnRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                address(this),
                block.timestamp
            )
        {
            // do nothing here
        } catch {
            emit SwapFailure(amountIn, amountOutMin, path);
            require(ignoreError, "swap failed");
            // if one of the swap fails, we do NOT revert and carry on
        }
    }

    /**
     * @notice Send $PLN tokens to specified wallets(burn and team)
     * @dev Callable by owner/operator
     */
    function sendPlearn(uint amount)
        external
        onlyOwnerOrOperator
    {
        require (amount > 0, "invalid amount");
        uint burnAmount = amount * plearnBurnRate / RATE_DENOMINATOR;
        // The rest goes to the team wallet.
        uint teamAmount = amount - burnAmount;
        IERC20Upgradeable(plearn).safeTransfer(plearnBurnAddress, burnAmount);
        IERC20Upgradeable(plearn).safeTransfer(plearnTeamAddress, teamAmount);
    }

    /**
     * @notice Deposit ETH for WETH
     * @dev Callable by owner/operator
     */
    function depositETH(uint amount)
        external
        onlyOwnerOrOperator
    {
        WETH.deposit{value: amount}();
    }

    /**
     * @notice Set PlearnRouter
     * @dev Callable by owner
     */
    function setPlearnRouter(address _plearnRouter) external onlyOwner {
        plearnRouter = IPlearnRouter02(_plearnRouter);
        emit NewPlearnRouter(msg.sender, _plearnRouter);
    }

    /**
     * @notice Set operator address
     * @dev Callable by owner
     */
    function setOperator(address _operatorAddress) external onlyOwner {
        operatorAddress = _operatorAddress;
        emit NewOperatorAddress(msg.sender, _operatorAddress);
    }

    /**
     * @notice Set address for `plearn burn`
     * @dev Callable by owner
     */
    function setPlearnBurnAddress(address _plearnBurnAddress) external onlyOwner {
        plearnBurnAddress = _plearnBurnAddress;
        emit NewPlearnBurnAddress(msg.sender, _plearnBurnAddress);
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
     * @notice transfer some BNB to the operator as gas fee
     * @dev Callable by owner
     */
    function topUpOperator(uint256 amount) external onlyOwner {
        require(amount <= operatorTopUpLimit, "too much");
        uint256 bnbBalance = address(this).balance;
        if (amount > bnbBalance) {
            // BNB not enough, get some BNB from WBNB
            // If WBNB balance is not enough, `withdraw` will `revert`.
            WETH.withdraw(amount - bnbBalance);
        }
        payable(operatorAddress).transfer(amount);
    }

    /**
     * @notice Set top-up limit
     * @dev Callable by owner
     */
    function setOperatorTopUpLimit(uint256 _operatorTopUpLimit) external onlyOwner {
        operatorTopUpLimit = _operatorTopUpLimit;
    }

    function addDestination(address addr) external onlyOwner {
        validDestination[addr] = true;
    }

    function removeDestination(address addr) external onlyOwner {
        validDestination[addr] = false;
    }

    function getPairAddress(
        address factory,
        uint256 cursor,
        uint256 size
    )
        external
        view
        returns (
            address[] memory pairs,
            uint256 nextCursor
        )
    {
        IPlearnFactory pcsFactory = IPlearnFactory(factory);
        uint256 maxLength = pcsFactory.allPairsLength();
        uint256 length = size;
        if (cursor >= maxLength) {
            address[] memory emptyList;
            return (emptyList, maxLength);
        }
        if (length > maxLength - cursor) {
            length = maxLength - cursor;
        }

        address[] memory values = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            address tempAddr = address(pcsFactory.allPairs(cursor+i));
            values[i] = tempAddr;
        }

        return (values, cursor + length);
    }

    function getPairTokens(
        address[] calldata lps,
        address account
    )
        external
        view
        returns (
            LPData[] memory
        )
    {
        LPData[] memory lpListData = new LPData[](lps.length);
        for (uint256 i = 0; i < lps.length; ++i) {
            IPlearnPair pair = IPlearnPair(lps[i]);
            lpListData[i].lpAddress = lps[i];
            lpListData[i].token0 = pair.token0();
            lpListData[i].token1 = pair.token1();
            (lpListData[i].token0Amt, lpListData[i].token1Amt, ) = pair.getReserves();
            lpListData[i].userBalance = pair.balanceOf(account);
            lpListData[i].totalSupply = pair.totalSupply();
        }
        return lpListData;
    }

    function _getTokenAmountMinFromLiquidity(uint _token0Amt, uint _token1Amt, uint _lpBalance, uint _totalSupply) internal view returns (uint _amountAMin, uint _amountBMin) {
        uint tokenAAmountPerLP = _token0Amt / _totalSupply;
            uint tokenASlippageAmount = tokenAAmountPerLP * slippageTolerance / SLIPPAGE_DENOMINATOR;
            uint amountAMinPerLP = tokenAAmountPerLP - tokenASlippageAmount;
            _amountAMin = amountAMinPerLP * _lpBalance;

            uint tokenBAmountPerLP = _token1Amt / _totalSupply;
            uint tokenBSlippageAmount = tokenBAmountPerLP * slippageTolerance / SLIPPAGE_DENOMINATOR;
            uint amountBMinPerLP = tokenBAmountPerLP - tokenBSlippageAmount;
            _amountBMin = amountBMinPerLP * _lpBalance;
    }


    receive() external payable {}
    fallback() external payable {}
    function _authorizeUpgrade(address) internal override onlyOwner {}
}