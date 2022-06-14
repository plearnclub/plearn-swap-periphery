// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import './interfaces/IPlearnFeeHandler.sol';
import "@plearn-libs/plearn-swap-core/contracts/interfaces/IPlearnPair.sol";

contract PlearnFeeManager is Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _pairs;

    address public plearn;
    IPlearnFeeHandler public plearnFeeHandler;

    constructor(
        address _plearn,
        address _plearnFeeHandler
    ) {
        plearn = _plearn;
        plearnFeeHandler = IPlearnFeeHandler(_plearnFeeHandler);
    }

    /**
     * @notice Sell all LP token from _pairs, buy back $PLN.
     * @dev Callable by owner
     */
    function processAllFee(bool ignoreError) external onlyOwner {
        IPlearnFeeHandler.RemoveLiquidityInfo[] memory liquidityList = new IPlearnFeeHandler.RemoveLiquidityInfo[](getPairDestinationLength());
        IPlearnFeeHandler.SwapInfo[] memory swapList = new IPlearnFeeHandler.SwapInfo[](getPairDestinationLength());
        uint pairsLength = getPairDestinationLength();
        
        for (uint256 i = 0; i < getPairDestinationLength(); ++i) {
            address pairAddress = EnumerableSet.at(_pairs, i);
            IPlearnPair pair = IPlearnPair(pairAddress);
            uint lpBalance = pair.balanceOf(address(plearnFeeHandler));

            liquidityList[i] = IPlearnFeeHandler.RemoveLiquidityInfo({
                    pair: pair,
                    amount: lpBalance,
                    amountAMin: 0,
                    amountBMin: 0
            });

            if (i == pairsLength - 1) {
                plearnFeeHandler.processFee(liquidityList, new IPlearnFeeHandler.SwapInfo[](0), ignoreError);
            }
        }

        for (uint256 i = 0; i < getPairDestinationLength(); ++i) {            
            address pairAddress = EnumerableSet.at(_pairs, i);
            IPlearnPair pair = IPlearnPair(pairAddress);
            address token0 = pair.token0();
            address token1 = pair.token1();

            address token = token0 == address(plearn) ? address(token1) : address(token0);
            address[] memory path = new address[](2);
            path[0] = token0 == address(plearn) ? address(token1) : address(token0);
            path[1] = token0 == address(plearn) ? address(token0) : address(token1);
            uint amountIn = IERC20(token).balanceOf(address(plearnFeeHandler));

            swapList[i] = IPlearnFeeHandler.SwapInfo({
                amountIn: amountIn,
                amountOutMin: 0,
                path: path
            });

            if (i == pairsLength - 1) {
                plearnFeeHandler.processFee(new IPlearnFeeHandler.RemoveLiquidityInfo[](0), swapList, ignoreError);
            }
        }

        uint plearnAmount = IERC20(plearn).balanceOf(address(plearnFeeHandler));
        plearnFeeHandler.sendPlearn(plearnAmount);
    }

    function addPairDestination(address _address) external onlyOwner {
        EnumerableSet.add(_pairs, _address);
    }

    function removePairDestination(address _address) external onlyOwner {
        EnumerableSet.remove(_pairs, _address);
    }

    function getPairDestinationLength() public view returns (uint256) {
        return EnumerableSet.length(_pairs);
    }

    function isPairDestination(address account) public view returns (bool) {
        return EnumerableSet.contains(_pairs, account);
    }

}