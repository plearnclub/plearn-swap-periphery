// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

interface IPlearnMigrator {
    function migrate(
        address token,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external;
}
