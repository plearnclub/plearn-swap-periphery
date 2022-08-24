// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '../interfaces/IWETH.sol';
import '../interfaces/IPlearnRouter02.sol';
import "@plearn-libs/plearn-swap-core/contracts/interfaces/IPlearnPair.sol";
import "@plearn-libs/plearn-swap-core/contracts/interfaces/IPlearnFactory.sol";

contract FeeHandler is Ownable {
    using SafeERC20 for IERC20;

    struct RemoveLiquidityInfo {
        IPlearnPair pair;
        uint amount;
        uint amountAMin;
        uint amountBMin;
    }

    struct SwapInfo {
        uint amountIn;
        uint amountOutMin;
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
    event RemoveLiquidityFailure(IPlearnPair pair, uint amount, uint amountAMin, uint amountBMin);
    event NewPlearnRouter(address indexed sender, address indexed router);
    event NewOperatorAddress(address indexed sender, address indexed operator);
    event NewPlearnBurnAddress(address indexed sender, address indexed burnAddress);

    address public plearn;
    IPlearnRouter02 public plearnRouter;
    address public operatorAddress; // address of the operator
    address public plearnBurnAddress;
    uint constant UNLIMITED_APPROVAL_AMOUNT = type(uint256).max;
    mapping(address => bool) public validDestination;
    IWETH WETH;

    // Maximum amount of BNB to top-up operator
    uint public operatorTopUpLimit;

    // Copied from: @openzeppelin/contracts/security/ReentrancyGuard.sol
    uint256 private constant _NOT_ENTERED = 0;
    uint256 private constant _ENTERED = 1;

    uint256 private _status;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;

        _;

        _status = _NOT_ENTERED;
    }

    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner() || msg.sender == operatorAddress, "Not owner/operator");
        _;
    }

    constructor(
        address _plearn,
        address _plearnRouter,
        address _operatorAddress,
        address _plearnBurnAddress,
        address[] memory destinations
    ) {
        plearn = _plearn;
        plearnRouter = IPlearnRouter02(_plearnRouter);
        operatorAddress = _operatorAddress;
        plearnBurnAddress = _plearnBurnAddress;
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
        RemoveLiquidityInfo[] calldata liquidityList,
        SwapInfo[] calldata swapList,
        bool ignoreError
    )
        external
        onlyOwnerOrOperator
    {
        for (uint256 i = 0; i < liquidityList.length; ++i) {
            removeLiquidity(liquidityList[i], ignoreError);
        }
        for (uint256 i = 0; i < swapList.length; ++i) {
            swap(swapList[i].amountIn, swapList[i].amountOutMin, swapList[i].path, ignoreError);
        }
    }

    function removeLiquidity(
        RemoveLiquidityInfo calldata info,
        bool ignoreError
    )
        internal
    {
        uint allowance = info.pair.allowance(address(this), address(plearnRouter));
        if (allowance < info.amount) {
            IERC20(address(info.pair)).safeApprove(address(plearnRouter), UNLIMITED_APPROVAL_AMOUNT);
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
            emit RemoveLiquidityFailure(info.pair, info.amount, info.amountAMin, info.amountBMin);
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
        address[] calldata path,
        bool ignoreError
    )
        internal
    {
        require(path.length > 1, "invalid path");
        require(validDestination[path[path.length - 1]], "invalid path");
        address token = path[0];
        uint tokenBalance = IERC20(token).balanceOf(address(this));
        amountIn = (amountIn > tokenBalance) ? tokenBalance : amountIn;
        // TODO: need to adjust `token0AmountOutMin` ?
        uint allowance = IERC20(token).allowance(address(this), address(plearnRouter));
        if (allowance < amountIn) {
            IERC20(token).safeApprove(address(plearnRouter), UNLIMITED_APPROVAL_AMOUNT);
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
        IERC20(plearn).safeTransfer(plearnBurnAddress, amount);
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
     * @notice Withdraw tokens from this smart contract
     * @dev Callable by owner
     */
    function withdraw(
        address tokenAddr,
        address payable to,
        uint amount
    )
        external
        nonReentrant
        onlyOwner
    {
        require(to != address(0), "invalid recipient");
        if (tokenAddr == address(0)) {
            (bool success, ) = to.call{ value: amount }("");
            require(success, "transfer BNB failed");
        }
        else {
            IERC20(tokenAddr).safeTransfer(to, amount);
        }
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
        IPlearnFactory psFactory = IPlearnFactory(factory);
        uint256 maxLength = psFactory.allPairsLength();
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
            address tempAddr = address(psFactory.allPairs(cursor+i));
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

    receive() external payable {}
    fallback() external payable {}
}