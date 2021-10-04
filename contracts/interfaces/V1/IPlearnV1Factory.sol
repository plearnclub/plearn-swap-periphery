// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

interface IPlearnV1Factory {
    function getExchange(address) external view returns (address);
}
