// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {RwaMock} from "src/mock/rwaMock.sol";

import {CONTRACT_REGISTRY_ACCESS} from "src/constants.sol";

import {NullAddress, InvalidName, InvalidSymbol} from "src/errors.sol";

/// @notice  Rwa Factory Contract Mock
/// @title   Rwa Factory Contract Mock
/// @dev     This is just a mock
/// @author  Usual Tech team
contract RwaFactoryMock is ReentrancyGuard {
    address private _usualDAO;

    IRegistryAccess internal _registryAccess;
    IRegistryContract internal _registryContract;

    address[] private _rwas;

    mapping(address => bool) private _isRwa;
    mapping(string => address) private _rwaSymbolToAddress;

    error InvalidDecimals();

    /*//////////////////////////////////////////////////////////////
                                Event
    //////////////////////////////////////////////////////////////*/

    event NewRwa(string name, string symbol, address rwa);
    event RemoveRwa(address indexed rwa);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address registryContract_) {
        if (registryContract_ == address(0)) {
            revert NullAddress();
        }
        _registryContract = IRegistryContract(registryContract_);
        _registryAccess = IRegistryAccess(_registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @notice  Create a new rwa token
    /// @param   name    the name of the token
    /// @param   symbol  the symbol of the token
    /// @return  address  the address of the new rwa token

    function createRwa(string calldata name, string calldata symbol, uint8 decimals)
        external
        returns (address)
    {
        return _createRwa(name, symbol, decimals);
    }

    function _createRwa(string calldata name, string calldata symbol, uint8 decimals)
        internal
        nonReentrant
        returns (address)
    {
        // Check if the name is not empty
        if (bytes(name).length == 0) {
            revert InvalidName();
        }

        // Check if the symbol is not empty
        if (bytes(symbol).length == 0) {
            revert InvalidSymbol();
        }

        if (decimals == 0) {
            revert InvalidDecimals();
        }

        // Create the new rwa token
        address rwa = address(new RwaMock(name, symbol, decimals, address(_registryContract)));

        // Add the rwa token to the token native asset contract
        _addRwa(rwa);

        // Emit the event
        emit NewRwa(name, symbol, rwa);
        return rwa;
    }

    /// @notice  addRwa method
    /// @dev     add an rwa token to the mapping
    /// @param   rwa_  address of the rwa token
    function _addRwa(address rwa_) internal {
        _rwas.push(rwa_);
        _isRwa[rwa_] = true;
        _rwaSymbolToAddress[ERC20(rwa_).symbol()] = rwa_;
    }

    /// @notice  removeRwa method
    /// @dev     remove an rwa token from the mapping
    /// @param   rwa  address of the rwa token
    function removeRwa(address rwa) external {
        if (!isRwa(rwa)) {
            revert NullAddress();
        }
        _removeRwa(rwa);
        _rwaSymbolToAddress[ERC20(rwa).symbol()] = address(0);
        emit RemoveRwa(rwa);
    }

    /// @notice  internal removeRwa method
    /// @param   rwa  address of the rwa token
    function _removeRwa(address rwa) internal {
        uint256 length = _rwas.length;
        for (uint256 i = 0; i < length;) {
            if (_rwas[i] == rwa) {
                _rwas[i] = _rwas[length - 1];
                _rwas.pop();
                _isRwa[rwa] = false;
                return;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice  hasRwaToken method
    /// @dev     check if the address has rwa token
    /// @param   account  address of the account
    /// @return  bool  .
    function hasRwaToken(address account) external view returns (bool) {
        uint256 length = _rwas.length;
        for (uint256 i = 0; i < length;) {
            if (ERC20(_rwas[i]).balanceOf(account) > 0) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice  isRwa method
    /// @dev     check if a token is a rwa token
    /// @param   token  address of the token
    /// @return  bool  .

    function isRwa(address token) public view returns (bool) {
        return _isRwa[token];
    }

    /// @notice  getRwaFromSymbol method
    /// @dev     get the address of a rwa token by its symbol
    /// @param   rwaSymbol  symbol of the rwa token
    /// @return  address  .
    function getRwaFromSymbol(string memory rwaSymbol) external view returns (address) {
        address rwa = _rwaSymbolToAddress[rwaSymbol];
        if (rwa == address(0)) {
            revert NullAddress();
        }
        return rwa;
    }

    /// @notice  getRwasLength method
    /// @dev     get the length of the rwa tokens array
    /// @return  uint256  .
    function getRwasLength() external view returns (uint256) {
        return _rwas.length;
    }
}
