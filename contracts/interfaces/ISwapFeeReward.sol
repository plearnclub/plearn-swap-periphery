// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

interface ISwapFeeReward {
    function swap(
        address account,
        address input,
        address output,
        uint256 amount
    ) external returns (bool);
}
