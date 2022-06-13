// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import "@plearn-libs/plearn-swap-core/contracts/interfaces/IPlearnPair.sol";

interface IPlearnFeeHandler {

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

    function processFee(
        RemoveLiquidityInfo[] calldata liquidityList,
        SwapInfo[] calldata swapList,
        bool ignoreError
    ) external;

    function sendPlearn(uint amount) external;

}
