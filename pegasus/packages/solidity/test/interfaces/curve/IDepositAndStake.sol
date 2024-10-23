// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IDepositStakeZap {
    function depositAndStake(
        address deposit,
        address lpToken,
        address gauge,
        uint256 nCoins,
        address[] calldata coins,
        uint256[] calldata amounts,
        uint256 minMintAmount,
        bool useUnderlying,
        address pool
    ) external payable;
}
