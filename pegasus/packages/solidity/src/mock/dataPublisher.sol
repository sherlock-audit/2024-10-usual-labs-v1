// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IDataPublisher} from "src/interfaces/oracles/IDataPublisher.sol";
import {CONTRACT_REGISTRY_ACCESS, DEFAULT_ADMIN_ROLE} from "src/constants.sol";

import {NotAuthorized, AlreadyWhitelisted, SameValue} from "src/errors.sol";
import {NotWhitelisted, PriceUpdateBlocked} from "src/mock/errors.sol";

contract DataPublisher is IDataPublisher {
    struct OracleResponse {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
        uint8 decimals;
    }

    IRegistryContract public registryContract;
    IRegistryAccess public registryAccess;

    /// @dev Mapping to track whitelisted publishers for each token.
    mapping(address => mapping(address => bool)) public publisherWhitelistPerToken;

    /// @dev Mapping to store Oracle responses per round ID for each token.
    mapping(address => mapping(uint80 => OracleResponse)) public tokenResponsesPerRoundId;

    /// @dev Mapping to keep track of the last round ID for each token.
    mapping(address => uint80) public lastRoundId;

    /// @dev Mapping to block or unblock price updates for each token.
    mapping(address => bool) public blockPriceUpdate;

    /// @notice Event emitted when new data is published for a token.
    event DataPublished(address indexed token, int256 indexed newData);

    /// @notice Event emitted when a new publisher is added for a token.
    event NewPublisher(address indexed token, address indexed publisher);

    /// @notice Event emitted when a publisher is removed for a token.
    event RemovePublisher(address indexed token, address indexed publisher);

    /// @notice Event emitted when price updates are blocked or unblocked for a token.
    event BlockUpdatePrice(address indexed token, bool blockPriceUpdate);

    /// @dev Modifier to restrict access to whitelisted publishers for a specific token.
    /// @param token The address of the token being accessed.
    modifier onlyWhitelistPublisher(address token) {
        if (!publisherWhitelistPerToken[token][msg.sender]) {
            revert NotWhitelisted();
        }
        _;
    }

    /// @dev Modifier to restrict access to the admin role.
    modifier onlyAdmin() {
        if (!IRegistryAccess(registryAccess).hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    /// @dev Modifier to restrict asset price updates when the price update is blocked for a specific token.
    /// @param token The address of the token being updated.
    modifier assetPriceUpdateNotBlock(address token) {
        // You can't push a new price for a blocked price update except for the admin
        if (
            blockPriceUpdate[token]
                && !IRegistryAccess(registryAccess).hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) {
            revert PriceUpdateBlocked();
        }
        _;
    }

    /// @notice Constructor for initializing the contract.
    /// @dev This constructor is used to set the initial state of the contract.
    /// @param registryContract_ The registry contract address.
    constructor(address registryContract_) {
        registryContract = IRegistryContract(registryContract_);
        registryAccess = IRegistryAccess(registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
    }

    /// @notice  Function to block or unblock the price update for a token
    /// @dev     Only the admin can call this function
    /// @dev     Only the admin will be able to push an update if a token is block
    /// @param   token  address of the token
    /// @param   blockPriceUpdate_  bool to block or unblock the price update
    function blockAssetPriceUpdate(address token, bool blockPriceUpdate_) external onlyAdmin {
        if (blockPriceUpdate[token] == blockPriceUpdate_) {
            revert SameValue();
        }
        blockPriceUpdate[token] = blockPriceUpdate_;
        emit BlockUpdatePrice(token, blockPriceUpdate_);
    }

    /// @notice Adds a publisher to the whitelist for a specific token.
    /// @dev This function is restricted to admin members and allows them to add a publisher to the whitelist
    /// for a specific token. It emits a `NewPublisher` event upon successful addition.
    /// @param token The address of the token for which the publisher is being added to the whitelist.
    /// @param publisher The address of the publisher to be added to the whitelist.
    function addWhitelistPublisher(address token, address publisher) external onlyAdmin {
        if (publisherWhitelistPerToken[token][publisher]) {
            revert AlreadyWhitelisted();
        }
        publisherWhitelistPerToken[token][publisher] = true;
        emit NewPublisher(token, publisher);
    }

    /// @notice Removes a publisher from the whitelist for a specific token.
    /// @dev This function is restricted to admin members and allows them to remove a publisher from the whitelist
    /// for a specific token. It emits a `RemovePublisher` event upon successful removal.
    /// @param token The address of the token for which the publisher is being removed from the whitelist.
    /// @param publisher The address of the publisher to be removed from the whitelist.
    function removeWhitelistPublisher(address token, address publisher) external onlyAdmin {
        if (!publisherWhitelistPerToken[token][publisher]) {
            revert NotWhitelisted();
        }
        publisherWhitelistPerToken[token][publisher] = false;
        emit RemovePublisher(token, publisher);
    }

    // @inheritdoc IDataPublisher
    function publishData(address token, int256 newData)
        external
        onlyWhitelistPublisher(token)
        assetPriceUpdateNotBlock(token)
    {
        uint80 newId = ++lastRoundId[token];
        uint8 decimals = IERC20Metadata(token).decimals();
        tokenResponsesPerRoundId[token][newId] = OracleResponse({
            roundId: newId, // You may need to update this value from an actual oracle
            answer: newData,
            timestamp: block.timestamp,
            success: true,
            decimals: decimals // You may need to adjust the decimals based on the token
        });

        lastRoundId[token] = newId;

        emit DataPublished(token, newData);
    }

    /// @notice Retrieves the last Oracle response for a specific token.
    /// @dev This function is view and allows anyone to retrieve the last Oracle response
    /// for a specific token based on the last recorded round ID.
    /// @param token The address of the token for which the last response is being retrieved.
    /// @return The last Oracle response as a memory struct.
    function getLastResponse(address token) external view returns (OracleResponse memory) {
        return tokenResponsesPerRoundId[token][lastRoundId[token]];
    }

    /// @notice Retrieves a specific Oracle response for a token and round ID.
    /// @dev This function is view and allows anyone to retrieve an Oracle response
    /// for a specific token and round ID.
    /// @param token The address of the token for which the response is being retrieved.
    /// @param roundId The specific round ID for which the response is being retrieved.
    /// @return The Oracle response as a memory struct for the given token and round ID.
    function getLastResponseId(address token, uint80 roundId)
        external
        view
        returns (OracleResponse memory)
    {
        return tokenResponsesPerRoundId[token][roundId];
    }

    /// @inheritdoc IDataPublisher
    function latestRoundData(address token)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 timestamp, uint8 decimals)
    {
        return (
            tokenResponsesPerRoundId[token][lastRoundId[token]].roundId,
            tokenResponsesPerRoundId[token][lastRoundId[token]].answer,
            tokenResponsesPerRoundId[token][lastRoundId[token]].timestamp,
            tokenResponsesPerRoundId[token][lastRoundId[token]].decimals
        );
    }

    /// @inheritdoc IDataPublisher
    function getRoundData(address token, uint80 roundId)
        external
        view
        returns (uint80 id, int256 answer, uint256 timestamp, uint8 decimals)
    {
        OracleResponse memory response = tokenResponsesPerRoundId[token][roundId];
        return (response.roundId, response.answer, response.timestamp, response.decimals);
    }

    /// @notice Checks if a publisher is whitelisted for a specific token.
    /// @param token The address of the token for which the publisher's whitelist status is being checked.
    /// @param publisher The address of the publisher.
    /// @return true if the publisher is whitelisted; otherwise, false.
    function isWhitelistPublisher(address token, address publisher) external view returns (bool) {
        return publisherWhitelistPerToken[token][publisher];
    }
}
