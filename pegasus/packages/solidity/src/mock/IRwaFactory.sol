// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IRwaFactory {
    function hasRwaToken(address account) external view returns (bool);

    function getRwaFromSymbol(string memory stbcSymbol) external view returns (address);
}
