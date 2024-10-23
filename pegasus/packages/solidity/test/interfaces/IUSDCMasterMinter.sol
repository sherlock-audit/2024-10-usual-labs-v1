// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IUSDCMasterMinter {
    function incrementMinterAllowance(uint256 _allowanceIncrement) external;

    function getWorker(address _controller) external view returns (address);
}
