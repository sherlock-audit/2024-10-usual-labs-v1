// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import {IUsualSP} from "src/interfaces/token/IUsualSP.sol";
import {IUsualX} from "src/interfaces/vaults/IUsualX.sol";
import {IUsual} from "src/interfaces/token/IUsual.sol";
import {IDaoCollateral} from "src/interfaces/IDaoCollateral.sol";

import {IDistributionModule} from "src/interfaces/distribution/IDistributionModule.sol";
import {IDistributionAllocator} from "src/interfaces/distribution/IDistributionAllocator.sol";
import {IDistributionOperator} from "src/interfaces/distribution/IDistributionOperator.sol";
import {IOffChainDistributionChallenger} from
    "src/interfaces/distribution/IOffChainDistributionChallenger.sol";

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {Normalize} from "src/utils/normalize.sol";

import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";

import {
    DEFAULT_ADMIN_ROLE,
    DISTRIBUTION_ALLOCATOR_ROLE,
    DISTRIBUTION_OPERATOR_ROLE,
    DISTRIBUTION_CHALLENGER_ROLE,
    PAUSING_CONTRACTS_ROLE,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USD0PP,
    SCALAR_ONE,
    BPS_SCALAR,
    CONTRACT_USUAL,
    CONTRACT_USUALX,
    CONTRACT_USUALSP,
    CONTRACT_DAO_COLLATERAL,
    USUAL_DISTRIBUTION_CHALLENGE_PERIOD,
    BASIS_POINT_BASE,
    LBT_DISTRIBUTION_SHARE,
    LYT_DISTRIBUTION_SHARE,
    IYT_DISTRIBUTION_SHARE,
    BRIBE_DISTRIBUTION_SHARE,
    ECO_DISTRIBUTION_SHARE,
    DAO_DISTRIBUTION_SHARE,
    MARKET_MAKERS_DISTRIBUTION_SHARE,
    USUALX_DISTRIBUTION_SHARE,
    USUALSTAR_DISTRIBUTION_SHARE,
    DISTRIBUTION_FREQUENCY_SCALAR
} from "src/constants.sol";

import {
    AmountIsZero,
    NullMerkleRoot,
    InvalidProof,
    InvalidInput,
    NullAddress,
    NullContract,
    SameValue,
    PercentagesSumNotEqualTo100Percent,
    CannotDistributeUsualMoreThanOnceADay,
    NoOffChainDistributionToApprove,
    NoTokensToClaim
} from "src/errors.sol";

/// @title DistributionModule
/// @notice This contract provides calculations for treasury yield analysis & distribution
/// @dev Implements upgradeable pattern and uses fixed point arithmetic for calculations
/// @author  Usual Tech team
contract DistributionModule is
    IDistributionModule,
    IDistributionAllocator,
    IDistributionOperator,
    IOffChainDistributionChallenger,
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IUsual;
    using SafeERC20 for IERC20Metadata;
    using CheckAccessControl for IRegistryAccess;
    using Normalize for uint256;

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a parameter used in the distribution calculations is updated
    /// @param parameterName Name of the parameter
    /// @param newValue New value of the parameter
    event ParameterUpdated(string parameterName, uint256 newValue);

    /// @notice Emitted when tokens are allocated to the off-chain distribution bucket
    /// @param amount Amount of tokens allocated
    event UsualAllocatedForOffChainClaim(uint256 amount);

    /// @notice Emitted when tokens are allocated to the UsualX bucket
    /// @param amount Amount of tokens allocated
    event UsualAllocatedForUsualX(uint256 amount);

    /// @notice Emitted when tokens are allocated to the UsualStar bucket
    /// @param amount Amount of tokens allocated
    event UsualAllocatedForUsualStar(uint256 amount);

    /// @notice Emitted when an off-chain distribution is queued by the distribution operator
    /// @param timestamp Timestamp of the distribution
    /// @param merkleRoot Merkle Root of the off-chain distribution
    event OffChainDistributionQueued(uint256 indexed timestamp, bytes32 merkleRoot);

    /// @notice Emitted when an unchallenged off-chain distribution older than the distribution challenge period is approved
    /// @param timestamp Timestamp of the distribution
    /// @param merkleRoot Merkle Root of the off-chain distribution approved
    event OffChainDistributionApproved(uint256 indexed timestamp, bytes32 merkleRoot);

    /// @notice Emitted when an off-chain distribution is claimed by an account
    /// @param account Account that claimed the tokens
    /// @param amount Amount of tokens claimed
    event OffChainDistributionClaimed(address indexed account, uint256 amount);

    /// @notice Emitted when the off-chain distribution queue is reset
    event OffChainDistributionQueueReset();

    /// @notice Emitted when an off-chain distribution is challenged
    /// @param timestamp Timestamp of the challenged distribution
    event OffChainDistributionChallenged(uint256 indexed timestamp);

    struct DistributionModuleStorageV0 {
        /// @notice Registry access contract
        IRegistryAccess registryAccess;
        /// @notice Registry contract
        IRegistryContract registryContract;
        /// @notice usd0PP contract
        IERC20Metadata usd0PP;
        /// @notice Usual token contract
        IUsual usual;
        /// @notice UsualX contract
        IUsualX usualX;
        /// @notice UsualSP contract
        IUsualSP usualSP;
        /// @notice DAO Collateral contract
        IDaoCollateral daoCollateral;
        /// @notice LBT bucket distribution percentage
        uint256 lbtDistributionShare;
        /// @notice LYT bucket distribution percentage
        uint256 lytDistributionShare;
        /// @notice IYT bucket distribution percentage
        uint256 iytDistributionShare;
        /// @notice Bribe bucket distribution percentage
        uint256 bribeDistributionShare;
        /// @notice Ecosystem bucket distribution percentage
        uint256 ecoDistributionShare;
        /// @notice DAO bucket distribution percentage
        uint256 daoDistributionShare;
        /// @notice Market makers bucket distribution percentage
        uint256 marketMakersDistributionShare;
        /// @notice UsualX bucket distribution percentage
        uint256 usualXDistributionShare;
        /// @notice UsualStar bucket distribution percentage
        uint256 usualStarDistributionShare;
        /// @notice D parameter
        uint256 d;
        /// @notice M0 parameter
        uint256 m0;
        /// @notice p0 parameter: initial price
        uint256 p0;
        /// @notice rate0 parameter: initial rate
        uint256 rate0;
        /// @notice RateMin parameter
        uint256 rateMin;
        /// @notice baseGamma parameter
        uint256 baseGamma;
        /// @notice usd0PP total supply at the time of deployment
        uint256 initialSupplyPp0;
        /// @notice Timestamp of the last on-chain distribution
        uint256 lastOnChainDistributionTimestamp;
        /// @notice Amount of tokens that can be minted for the off-chain distribution
        uint256 offChainDistributionMintCap;
        /// @notice Queue of off-chain distributions
        QueuedOffChainDistribution[] offChainDistributionQueue;
        /// @notice Timestamp of the latest off-chain distribution update that is claimable
        uint256 offChainDistributionTimestamp;
        /// @notice Merkle root of the latest off-chain distribution update that is claimable and after challenge period
        /// @dev Merkle tree should always include the total amount of tokens that account can claim and could claim in the past.
        bytes32 offChainDistributionMerkleRoot;
        /// @notice Mapping of the claimed tokens for each account. Used to prevent double claiming after a new distribution is approved.
        mapping(address offChainClaimer => uint256 amount) claimedByOffChainClaimer;
    }

    // keccak256(abi.encode(uint256(keccak256("DistributionModule.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant DistributionModuleStorageV0Location =
        0xfe38e877893749f31d716df8c21b1fcb408307d7596d0d90c0ec8782cacd9b00;

    // solhint-disable
    /// @dev Returns the storage struct of the contract
    function _distributionModuleStorageV0()
        internal
        pure
        returns (DistributionModuleStorageV0 storage $)
    {
        bytes32 position = DistributionModuleStorageV0Location;
        assembly {
            $.slot := position
        }
    }
    // solhint-enable

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             Initializer
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract
    /// @param _registryContract Address of the registry contract
    /// @param rate0 Initial rate0 value
    function initialize(IRegistryContract _registryContract, uint256 rate0) public initializer {
        if (address(_registryContract) == address(0)) {
            revert NullContract();
        }
        if (rate0 == 0) {
            revert InvalidInput();
        }

        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        $.registryContract = _registryContract;
        $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));

        $.usual = IUsual($.registryContract.getContract(CONTRACT_USUAL));
        $.usd0PP = IERC20Metadata($.registryContract.getContract(CONTRACT_USD0PP));
        $.daoCollateral = IDaoCollateral($.registryContract.getContract(CONTRACT_DAO_COLLATERAL));
        $.usualSP = IUsualSP($.registryContract.getContract(CONTRACT_USUALSP));
        $.usualX = IUsualX($.registryContract.getContract(CONTRACT_USUALX));

        // Initialize parameters (scaled values in basis points)
        $.lbtDistributionShare = LBT_DISTRIBUTION_SHARE;
        $.lytDistributionShare = LYT_DISTRIBUTION_SHARE;
        $.iytDistributionShare = IYT_DISTRIBUTION_SHARE;
        $.bribeDistributionShare = BRIBE_DISTRIBUTION_SHARE;
        $.ecoDistributionShare = ECO_DISTRIBUTION_SHARE;
        $.daoDistributionShare = DAO_DISTRIBUTION_SHARE;
        $.marketMakersDistributionShare = MARKET_MAKERS_DISTRIBUTION_SHARE;
        $.usualXDistributionShare = USUALX_DISTRIBUTION_SHARE;
        $.usualStarDistributionShare = USUALSTAR_DISTRIBUTION_SHARE;
        $.d = 2500; // 25% in basis point precision
        $.m0 = 10e18; // initial supply factor
        $.rateMin = 50; // 0.5% in basis point precision
        $.baseGamma = BASIS_POINT_BASE; // 100% in basis points precision

        // Memoize initial values (immutable)
        $.initialSupplyPp0 = $.usd0PP.totalSupply();
        $.p0 = _getUSD0Price($);
        $.rate0 = rate0;
    }

    /// @notice Checks if the caller has DISTRIBUTION_ALLOCATOR_ROLE role
    /// @param $ Storage struct of the contract
    function _requireOnlyDistributionAllocator(DistributionModuleStorageV0 storage $)
        internal
        view
    {
        $.registryAccess.onlyMatchingRole(DISTRIBUTION_ALLOCATOR_ROLE);
    }

    /// @notice Ensures that the caller is the pausing contracts role (PAUSING_CONTRACTS_ROLE).
    function _requireOnlyPausingContractsRole() internal view {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
    }

    /// @notice Ensures that the caller is the operator role (DISTRIBUTION_OPERATOR_ROLE).
    /// @param $ Storage struct of the contract
    function _requireOnlyOperator(DistributionModuleStorageV0 storage $) internal view {
        $.registryAccess.onlyMatchingRole(DISTRIBUTION_OPERATOR_ROLE);
    }

    /// @notice Ensures that the caller is the challenger role (DISTRIBUTION_CHALLENGER_ROLE).
    /// @param $ Storage struct of the contract
    function _requireOnlyChallenger(DistributionModuleStorageV0 storage $) internal view {
        $.registryAccess.onlyMatchingRole(DISTRIBUTION_CHALLENGER_ROLE);
    }

    /// @notice Pauses the contract
    /// @dev Can only be called by the PAUSING_CONTRACTS_ROLE
    function pause() external {
        _requireOnlyPausingContractsRole();
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev Can only be called by the DEFAULT_ADMIN_ROLE
    function unpause() external {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /// @inheritdoc IDistributionModule
    function getBucketsDistribution()
        external
        view
        returns (
            uint256 lbt,
            uint256 lyt,
            uint256 iyt,
            uint256 bribe,
            uint256 eco,
            uint256 dao,
            uint256 marketMakers,
            uint256 usualX,
            uint256 usualStar
        )
    {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();

        lbt = $.lbtDistributionShare;
        lyt = $.lytDistributionShare;
        iyt = $.iytDistributionShare;
        bribe = $.bribeDistributionShare;
        eco = $.ecoDistributionShare;
        dao = $.daoDistributionShare;
        marketMakers = $.marketMakersDistributionShare;
        usualX = $.usualXDistributionShare;
        usualStar = $.usualStarDistributionShare;
    }

    /// @inheritdoc IDistributionModule
    function calculateSt(uint256 supplyPpt, uint256 pt) external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return _calculateSt($, supplyPpt, pt);
    }

    /// @inheritdoc IDistributionModule
    function calculateRt(uint256 ratet, uint256 p90Rate) external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return _calculateRt($, ratet, p90Rate);
    }

    /// @inheritdoc IDistributionModule
    function calculateKappa(uint256 ratet) external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return _calculateKappa($, ratet);
    }

    function calculateGamma() external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return _calculateGamma($);
    }

    /// @inheritdoc IDistributionModule
    function calculateMt(uint256 st, uint256 rt, uint256 kappa) external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();

        return _calculateMt($, st, rt, kappa);
    }

    /// @inheritdoc IDistributionModule
    function calculateUsualDist(uint256 ratet, uint256 p90Rate)
        public
        view
        returns (uint256 st, uint256 rt, uint256 kappa, uint256 mt, uint256 usualDist)
    {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();

        return _calculateUsualDistribution($, ratet, p90Rate);
    }

    /// @inheritdoc IDistributionModule
    function claimOffChainDistribution(address account, uint256 amount, bytes32[] calldata proof)
        external
        whenNotPaused
        nonReentrant
    {
        if (account == address(0)) {
            revert NullAddress();
        }
        if (amount == 0) {
            revert AmountIsZero();
        }

        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        if ($.offChainDistributionTimestamp == 0) {
            revert NoTokensToClaim();
        }

        if (!_verifyOffChainDistributionMerkleProof($, account, amount, proof)) {
            revert InvalidProof();
        }

        uint256 claimedUpToNow = $.claimedByOffChainClaimer[account];

        if (claimedUpToNow >= amount) {
            revert NoTokensToClaim();
        }

        uint256 amountToSend = amount - claimedUpToNow;

        if (amountToSend > $.offChainDistributionMintCap) {
            revert NoTokensToClaim();
        }

        $.offChainDistributionMintCap -= amountToSend;
        $.claimedByOffChainClaimer[account] = amount;

        emit OffChainDistributionClaimed(account, amountToSend);
        $.usual.mint(account, amountToSend);
    }

    /// @inheritdoc IDistributionModule
    function approveUnchallengedOffChainDistribution() external whenNotPaused {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();

        uint256 queueLength = $.offChainDistributionQueue.length;
        if (queueLength == 0) {
            revert NoOffChainDistributionToApprove();
        }

        uint256 candidateTimestamp = $.offChainDistributionTimestamp;
        bytes32 candidateMerkleRoot = bytes32(0);

        uint256 amountOfDistributionsToRemove = 0;
        uint256[] memory indicesToRemove = new uint256[](queueLength);

        for (uint256 i; i < queueLength;) {
            QueuedOffChainDistribution storage distribution = $.offChainDistributionQueue[i];

            bool isAfterChallengePeriod =
                block.timestamp >= distribution.timestamp + USUAL_DISTRIBUTION_CHALLENGE_PERIOD;
            bool isNewerThanCandidate = distribution.timestamp > candidateTimestamp;

            if (isAfterChallengePeriod && isNewerThanCandidate) {
                candidateMerkleRoot = distribution.merkleRoot;
                candidateTimestamp = distribution.timestamp;
            }

            if (isAfterChallengePeriod) {
                // NOTE: We store the index to remove to avoid modifying the array while iterating.
                // NOTE: After successful approval queue should have only elements older than challenge period.
                indicesToRemove[amountOfDistributionsToRemove] = i;
                amountOfDistributionsToRemove++;
            }

            unchecked {
                ++i;
            }
        }

        if (candidateTimestamp <= $.offChainDistributionTimestamp) {
            revert NoOffChainDistributionToApprove();
        }

        for (uint256 i = amountOfDistributionsToRemove; i > 0;) {
            uint256 indexToRemove = indicesToRemove[i - 1];

            // NOTE: $.offChainDistributionQueue.length cannot be cached since it can decrease with each loop iteration
            $.offChainDistributionQueue[indexToRemove] =
                $.offChainDistributionQueue[$.offChainDistributionQueue.length - 1];
            $.offChainDistributionQueue.pop();

            unchecked {
                --i;
            }
        }

        $.offChainDistributionMerkleRoot = candidateMerkleRoot;
        $.offChainDistributionTimestamp = candidateTimestamp;

        emit OffChainDistributionApproved(
            $.offChainDistributionTimestamp, $.offChainDistributionMerkleRoot
        );
    }

    /// @inheritdoc IDistributionModule
    function getLastOnChainDistributionTimestamp() external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return $.lastOnChainDistributionTimestamp;
    }

    /// @inheritdoc IDistributionModule
    function getOffChainDistributionData()
        external
        view
        returns (uint256 timestamp, bytes32 merkleRoot)
    {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return ($.offChainDistributionTimestamp, $.offChainDistributionMerkleRoot);
    }

    /// @inheritdoc IDistributionModule
    function getOffChainTokensClaimed(address account) external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return $.claimedByOffChainClaimer[account];
    }

    /// @inheritdoc IDistributionModule
    function getOffChainDistributionMintCap() external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return $.offChainDistributionMintCap;
    }

    /// @inheritdoc IDistributionModule
    function getOffChainDistributionQueue()
        external
        view
        returns (QueuedOffChainDistribution[] memory)
    {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return $.offChainDistributionQueue;
    }

    /// @inheritdoc IDistributionAllocator
    function setD(uint256 _d) external {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        _requireOnlyDistributionAllocator($);

        if (_d == 0) {
            revert InvalidInput();
        }
        if ($.d == _d) revert SameValue();

        $.d = _d;
        emit ParameterUpdated("d", _d);
    }

    /// @inheritdoc IDistributionAllocator
    function getD() external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return $.d;
    }

    /// @inheritdoc IDistributionAllocator
    function setM0(uint256 _m0) external {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        _requireOnlyDistributionAllocator($);

        if (_m0 == 0) {
            revert InvalidInput();
        }

        if ($.m0 == _m0) revert SameValue();
        $.m0 = _m0;
        emit ParameterUpdated("m0", _m0);
    }

    /// @inheritdoc IDistributionAllocator
    function getM0() external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return $.m0;
    }

    /// @inheritdoc IDistributionAllocator
    function setRateMin(uint256 _rateMin) external {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        _requireOnlyDistributionAllocator($);

        if (_rateMin == 0) {
            revert InvalidInput();
        }

        if ($.rateMin == _rateMin) revert SameValue();
        $.rateMin = _rateMin;
        emit ParameterUpdated("rateMin", _rateMin);
    }

    /// @inheritdoc IDistributionAllocator
    function getRateMin() external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return $.rateMin;
    }

    /// @inheritdoc IDistributionAllocator
    function setBaseGamma(uint256 _baseGamma) external {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        _requireOnlyDistributionAllocator($);

        if (_baseGamma == 0) {
            revert InvalidInput();
        }

        if ($.baseGamma == _baseGamma) revert SameValue();
        $.baseGamma = _baseGamma;
        emit ParameterUpdated("baseGamma", _baseGamma);
    }

    /// @inheritdoc IDistributionAllocator
    function getBaseGamma() external view returns (uint256) {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        return $.baseGamma;
    }

    /// @inheritdoc IDistributionAllocator
    function setBucketsDistribution(
        uint256 _lbt,
        uint256 _lyt,
        uint256 _iyt,
        uint256 _bribe,
        uint256 _eco,
        uint256 _dao,
        uint256 _marketMakers,
        uint256 _usualP,
        uint256 _usualStar
    ) external {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();

        _requireOnlyDistributionAllocator($);

        uint256 total = 0;
        total += _lbt;
        total += _lyt;
        total += _iyt;
        total += _bribe;
        total += _eco;
        total += _dao;
        total += _marketMakers;
        total += _usualP;
        total += _usualStar;

        if (total != BASIS_POINT_BASE) revert PercentagesSumNotEqualTo100Percent();

        _setLbt($, _lbt);
        _setLyt($, _lyt);
        _setIyt($, _iyt);
        _setBribe($, _bribe);
        _setEco($, _eco);
        _setDao($, _dao);
        _setMarketMakers($, _marketMakers);
        _setUsualP($, _usualP);
        _setUsualStar($, _usualStar);
    }

    /// @inheritdoc IDistributionOperator
    function distributeUsualToBuckets(uint256 ratet, uint256 p90Rate)
        external
        whenNotPaused
        nonReentrant
    {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        _requireOnlyOperator($);

        if (ratet == 0 || ratet >= BPS_SCALAR) {
            revert InvalidInput();
        }

        if (p90Rate == 0 || p90Rate >= BPS_SCALAR) {
            revert InvalidInput();
        }

        if (block.timestamp < $.lastOnChainDistributionTimestamp + DISTRIBUTION_FREQUENCY_SCALAR) {
            revert CannotDistributeUsualMoreThanOnceADay();
        }

        (,,,, uint256 usualDistribution) = _calculateUsualDistribution($, ratet, p90Rate);

        $.lastOnChainDistributionTimestamp = block.timestamp;

        _distributeToOffChainBucket($, usualDistribution);
        _distributeToUsualXBucket($, usualDistribution);
        _distributeToUsualStarBucket($, usualDistribution);
    }

    /// @inheritdoc IDistributionOperator
    function queueOffChainUsualDistribution(bytes32 _merkleRoot) external whenNotPaused {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        _requireOnlyOperator($);

        if (_merkleRoot == bytes32(0)) {
            revert NullMerkleRoot();
        }

        $.offChainDistributionQueue.push(
            QueuedOffChainDistribution({timestamp: block.timestamp, merkleRoot: _merkleRoot})
        );
        emit OffChainDistributionQueued(block.timestamp, _merkleRoot);
    }

    /// @inheritdoc IDistributionOperator
    function resetOffChainDistributionQueue() external whenNotPaused {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        _requireOnlyOperator($);

        delete $.offChainDistributionQueue;
        emit OffChainDistributionQueueReset();
    }

    /// @inheritdoc IOffChainDistributionChallenger
    function challengeOffChainDistribution(uint256 _timestamp) external whenNotPaused {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        _requireOnlyChallenger($);

        _markQueuedOffChainDistributionsAsChallenged($, _timestamp);
        emit OffChainDistributionChallenged(_timestamp);
    }

    /// @notice Marks off-chain distributions older than the specified timestamp as challenged
    /// @param $ Storage struct of the contract
    /// @param _timestamp Timestamp before which the off-chain distribution will be challenged
    function _markQueuedOffChainDistributionsAsChallenged(
        DistributionModuleStorageV0 storage $,
        uint256 _timestamp
    ) internal {
        uint256 i = 0;
        while (i < $.offChainDistributionQueue.length) {
            QueuedOffChainDistribution storage distribution = $.offChainDistributionQueue[i];
            bool isAfterChallengePeriod =
                block.timestamp >= distribution.timestamp + USUAL_DISTRIBUTION_CHALLENGE_PERIOD;

            if (distribution.timestamp < _timestamp && !isAfterChallengePeriod) {
                // Swap with the last element and pop
                $.offChainDistributionQueue[i] =
                    $.offChainDistributionQueue[$.offChainDistributionQueue.length - 1];
                $.offChainDistributionQueue.pop();
                // Don't increment i, as we need to check the swapped element
            } else {
                // Only increment if we didn't remove an element
                i++;
            }
        }
    }

    /// @notice Increases the mint cap for the off-chain distribution by the calculated share of the distribution
    /// @param $ Storage struct of the contract
    /// @param usualDistribution Amount of Usual to distribute to all buckets
    /// @dev If the off-chain buckets share is 0, the function will return without increasing the mint cap
    function _distributeToOffChainBucket(
        DistributionModuleStorageV0 storage $,
        uint256 usualDistribution
    ) internal {
        uint256 offChainBucketsShare =
            BASIS_POINT_BASE - $.usualXDistributionShare - $.usualStarDistributionShare;
        if (offChainBucketsShare == 0) {
            return;
        }

        uint256 amount =
            Math.mulDiv(usualDistribution, offChainBucketsShare, BPS_SCALAR, Math.Rounding.Floor);

        $.offChainDistributionMintCap += amount;

        emit UsualAllocatedForOffChainClaim(amount);
    }

    /// @notice Mints Usual to UsualX and starts the yield distribution by the calculated share of the distribution
    /// @param $ Storage struct of the contract
    /// @param usualDistribution Amount of Usual to distribute to all buckets
    /// @dev If the UsualX share is 0, the function will return without minting Usual to UsualX
    function _distributeToUsualXBucket(
        DistributionModuleStorageV0 storage $,
        uint256 usualDistribution
    ) internal {
        if ($.usualXDistributionShare == 0) {
            return;
        }

        uint256 amount = Math.mulDiv(
            usualDistribution, $.usualXDistributionShare, BPS_SCALAR, Math.Rounding.Floor
        );

        emit UsualAllocatedForUsualX(amount);

        $.usual.mint(address($.usualX), amount);
        $.usualX.startYieldDistribution(
            amount, block.timestamp, block.timestamp + DISTRIBUTION_FREQUENCY_SCALAR
        );
    }

    /// @notice Mints Usual to this contract, increases the allowance for UsualSP and starts the yield distribution by the calculated share of the distribution
    /// @param $ Storage struct of the contract
    /// @param usualDistribution Amount of Usual to distribute to all buckets
    /// @dev If the UsualStar share is 0, the function will return without minting Usual to this contract
    function _distributeToUsualStarBucket(
        DistributionModuleStorageV0 storage $,
        uint256 usualDistribution
    ) internal {
        if ($.usualStarDistributionShare == 0) {
            return;
        }

        uint256 amount = Math.mulDiv(
            usualDistribution, $.usualStarDistributionShare, BPS_SCALAR, Math.Rounding.Floor
        );

        emit UsualAllocatedForUsualStar(amount);

        $.usual.mint(address(this), amount);
        $.usual.safeIncreaseAllowance(address($.usualSP), amount);

        $.usualSP.startRewardDistribution(
            amount, block.timestamp, block.timestamp + DISTRIBUTION_FREQUENCY_SCALAR
        );
    }

    /// @notice Sets the LBT distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _lbt LBT distribution percentage
    function _setLbt(DistributionModuleStorageV0 storage $, uint256 _lbt) internal {
        $.lbtDistributionShare = _lbt;
        emit ParameterUpdated("lbt", _lbt);
    }

    /// @notice Sets the LYT distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _lyt LYT distribution percentage
    function _setLyt(DistributionModuleStorageV0 storage $, uint256 _lyt) internal {
        $.lytDistributionShare = _lyt;
        emit ParameterUpdated("lyt", _lyt);
    }

    /// @notice Sets the IYT distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _iyt IYT distribution percentage
    function _setIyt(DistributionModuleStorageV0 storage $, uint256 _iyt) internal {
        $.iytDistributionShare = _iyt;
        emit ParameterUpdated("iyt", _iyt);
    }

    /// @notice Sets the Bribe distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _bribe Bribe distribution percentage
    function _setBribe(DistributionModuleStorageV0 storage $, uint256 _bribe) internal {
        $.bribeDistributionShare = _bribe;
        emit ParameterUpdated("bribe", _bribe);
    }

    /// @notice Sets the Eco distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _eco Eco distribution percentage
    function _setEco(DistributionModuleStorageV0 storage $, uint256 _eco) internal {
        $.ecoDistributionShare = _eco;
        emit ParameterUpdated("eco", _eco);
    }

    /// @notice Sets the DAO distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _dao DAO distribution percentage
    function _setDao(DistributionModuleStorageV0 storage $, uint256 _dao) internal {
        $.daoDistributionShare = _dao;
        emit ParameterUpdated("dao", _dao);
    }

    /// @notice Sets the MarketMakers distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _marketMakers MarketMakers distribution percentage
    function _setMarketMakers(DistributionModuleStorageV0 storage $, uint256 _marketMakers)
        internal
    {
        $.marketMakersDistributionShare = _marketMakers;
        emit ParameterUpdated("marketMakers", _marketMakers);
    }

    /// @notice Sets the UsualP distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _usualX UsualX distribution percentage
    function _setUsualP(DistributionModuleStorageV0 storage $, uint256 _usualX) internal {
        $.usualXDistributionShare = _usualX;
        emit ParameterUpdated("usualX", _usualX);
    }

    /// @notice Sets the UsualStar distribution percentage
    /// @param $ Storage struct of the contract
    /// @param _usualStar UsualStar distribution percentage
    function _setUsualStar(DistributionModuleStorageV0 storage $, uint256 _usualStar) internal {
        $.usualStarDistributionShare = _usualStar;
        emit ParameterUpdated("usualStar", _usualStar);
    }

    /// @notice Calculates gamma scaled since lastOnChainDistributionTimestamp
    /// @param $ Storage struct of the contract
    /// @return Gamma scale factor
    function _calculateGamma(DistributionModuleStorageV0 storage $)
        internal
        view
        returns (uint256)
    {
        uint256 timePassed = block.timestamp - $.lastOnChainDistributionTimestamp;
        if (timePassed <= DISTRIBUTION_FREQUENCY_SCALAR || $.lastOnChainDistributionTimestamp == 0)
        {
            return Math.mulDiv($.baseGamma, SCALAR_ONE, BPS_SCALAR, Math.Rounding.Floor);
        }
        uint256 denominator =
            Math.mulDiv(SCALAR_ONE, timePassed, DISTRIBUTION_FREQUENCY_SCALAR, Math.Rounding.Floor);
        uint256 numerator = Math.mulDiv($.baseGamma, SCALAR_ONE, BPS_SCALAR, Math.Rounding.Floor);
        return Math.mulDiv(numerator, SCALAR_ONE, denominator, Math.Rounding.Floor);
    }

    /// @notice Calculates the UsualDist value
    /// @dev Raw equation: UsualDist = (d * Mt * supplyPpt * pt) / (365 days)
    /// @param mt Mt value (scaled by SCALAR_ONE)
    /// @param supplyPpt Current supply (scaled by SCALAR_ONE)
    /// @param pt Current price (scaled by SCALAR_ONE)
    /// @return UsualDist value (raw, not scaled)
    function _calculateDistribution(uint256 mt, uint256 supplyPpt, uint256 pt)
        internal
        view
        returns (uint256)
    {
        DistributionModuleStorageV0 storage $ = _distributionModuleStorageV0();
        // NOTE: d has BPS precision
        uint256 result = Math.mulDiv($.d, mt, BPS_SCALAR, Math.Rounding.Floor); // scales mt by BPS_SCALAR then divides by BPS_SCALAR to keep the same scale
        result = Math.mulDiv(result, supplyPpt, SCALAR_ONE, Math.Rounding.Floor); // 10**18 * 10**18 / 10**18 = 10**18
        result = Math.mulDiv(result, pt, SCALAR_ONE, Math.Rounding.Floor); // 10**18 * 10**18 / 10**18 = 10**18

        return Math.mulDiv(result, 1, 365, Math.Rounding.Floor);
    }

    /// @notice Returns the price of usd0 token
    /// @dev $1 unless CBR is on
    /// @param $ Storage struct of the contract
    function _getUSD0Price(DistributionModuleStorageV0 storage $) internal view returns (uint256) {
        if ($.daoCollateral.isCBROn()) {
            uint256 cbr = $.daoCollateral.cbrCoef();
            return Math.mulDiv(SCALAR_ONE, cbr, SCALAR_ONE, Math.Rounding.Floor);
        }
        return SCALAR_ONE;
    }

    /// @notice Calculates the Rt value
    /// @param $ Storage struct of the contract
    /// @param ratet Current rate in BPS
    /// @param p90Rate 90th percentile rate (scaled by BPS_SCALAR)
    /// @return Rt value (scaled by SCALAR_ONE)
    function _calculateRt(DistributionModuleStorageV0 storage $, uint256 ratet, uint256 p90Rate)
        internal
        view
        returns (uint256)
    {
        uint256 maxRate = ratet > $.rateMin ? ratet : $.rateMin; // scaled by 10_000
        uint256 minMaxRate = p90Rate < maxRate ? p90Rate : maxRate; // scaled by 10_000
        uint256 result = Math.mulDiv(SCALAR_ONE, minMaxRate, $.rate0, Math.Rounding.Floor); // scales minMaxRate by BPS_SCALAR then divides by $.rate0 to keep the same scale
        return result;
    }

    /// @notice Calculates the St value
    /// @param $ Storage struct of the contract
    /// @param supplyUSD0PP Current supply (scaled by SCALAR_ONE)
    /// @param pt Current price (scaled by SCALAR_ONE)
    /// @return St value (scaled by SCALAR_ONE)
    function _calculateSt(DistributionModuleStorageV0 storage $, uint256 supplyUSD0PP, uint256 pt)
        internal
        view
        returns (uint256)
    {
        // NOTE: everything has 10^18 precision
        uint256 numerator = Math.mulDiv($.initialSupplyPp0, $.p0, SCALAR_ONE); // scaled by 10**18 * 10**18 / 10**18 = 10**18
        uint256 denominator = Math.mulDiv(supplyUSD0PP, pt, SCALAR_ONE); // scaled by 10**18 * 10**18 / 10**18 = 10**18
        // NOTE: Good up to 10_000_000_000_000 supply, 10_000_000_000 price, with 10**18 precision
        // NOTE: (2^256-1) > (10000000000000*10**18)*(10000000000*10**18)*10**18
        uint256 result = Math.mulDiv(SCALAR_ONE, numerator, denominator, Math.Rounding.Floor); // scales numerator by 10**18 then divides by 10**18 to keep the same scale

        return result < SCALAR_ONE ? result : SCALAR_ONE;
    }

    /// @notice Calculates the Kappa value
    /// @param $ Storage struct of the contract
    /// @param ratet Current rate in BPS
    /// @return Kappa value (scaled by SCALAR_ONE)
    function _calculateKappa(DistributionModuleStorageV0 storage $, uint256 ratet)
        internal
        view
        returns (uint256)
    {
        uint256 maxRate = ratet > $.rateMin ? ratet : $.rateMin; // scaled by 10_000
        uint256 numerator = Math.mulDiv($.m0, maxRate, BPS_SCALAR); // scaled by 10**18 * 10_000 /10_000 = 10**18
        uint256 denominator = Math.mulDiv(_calculateGamma($), $.rate0, BPS_SCALAR); // scaled by 10**18 * 10**5 / 10**5 = 10**18
        return Math.mulDiv(numerator, SCALAR_ONE, denominator, Math.Rounding.Floor); // scales numerator 10*18 then divides to keep 10**18 scale
    }

    /// @notice Calculates the Mt value
    /// @param $ Storage struct of the contract
    /// @param st St value (scaled by SCALAR_ONE)
    /// @param rt Rt value (scaled by SCALAR_ONE)
    /// @param kappa Kappa value (scaled by SCALAR_ONE)
    /// @return Mt value (scaled by SCALAR_ONE)
    function _calculateMt(
        DistributionModuleStorageV0 storage $,
        uint256 st,
        uint256 rt,
        uint256 kappa
    ) internal view returns (uint256) {
        // (10*10**18*) * 10**18 = 10**37
        uint256 numerator = Math.mulDiv($.m0, st, SCALAR_ONE, Math.Rounding.Floor); // scaled by 10**18 * 10**18 / 10**18 = 10**18
        numerator = Math.mulDiv(numerator, rt, SCALAR_ONE, Math.Rounding.Floor); // scaled by 10**18 * 10**18 / 10**18 = 10**18
        uint256 result = Math.mulDiv(numerator, SCALAR_ONE, _calculateGamma($)); // scales numerator by 10**18  then divides by 10**18  to keep the same scale
        return result < kappa ? result : kappa;
    }

    /// @notice Calculates all values: St, Rt, Mt, and UsualDist
    /// @param ratet The current interest rate with BPS precision
    /// @param p90Rate The 90th percentile interest rate over the last 60 days with BPS precision
    /// @return st St value (scaled by SCALAR_ONE)
    /// @return rt Rt value (scaled by SCALAR_ONE)
    /// @return kappa Kappa value (scaled by SCALAR_ONE)
    /// @return mt Mt value (scaled by SCALAR_ONE)
    /// @return usualDist UsualDist value (raw, not scaled)
    function _calculateUsualDistribution(
        DistributionModuleStorageV0 storage $,
        uint256 ratet,
        uint256 p90Rate
    )
        internal
        view
        returns (uint256 st, uint256 rt, uint256 kappa, uint256 mt, uint256 usualDist)
    {
        uint256 currentSupplyUsd0PP = $.usd0PP.totalSupply();
        uint256 pt = _getUSD0Price($);

        st = _calculateSt($, currentSupplyUsd0PP, pt);
        rt = _calculateRt($, ratet, p90Rate);
        kappa = _calculateKappa($, ratet);
        mt = _calculateMt($, st, rt, kappa);
        usualDist = _calculateDistribution(mt, currentSupplyUsd0PP, pt);
    }

    /// @notice Verifies the off-chain distribution Merkle proof
    /// @param $ Storage struct of the contract
    /// @param account Account to claim for
    /// @param amount Amount of Usual token to claim
    /// @param proof Merkle proof
    function _verifyOffChainDistributionMerkleProof(
        DistributionModuleStorageV0 storage $,
        address account,
        uint256 amount,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
        return MerkleProof.verify(proof, $.offChainDistributionMerkleRoot, leaf);
    }
}
