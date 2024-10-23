// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC4626Upgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {YIELD_PRECISION} from "src/constants.sol";
/**
 * @title AbstractYieldBearingVault
 * @dev Abstract contract for a vault where shares appreciate in value due to yield accrual
 */

abstract contract YieldBearingVault is ERC4626Upgradeable {
    /// @custom:storage-location erc7201:YieldBearingVault.storage.v1
    struct YieldDataStorage {
        /// @notice Total assets deposited through deposit, tracked separately from assets reserved for yield. It excludes fees
        uint256 totalDeposits;
        /// @notice Yield tokens accrued per second
        uint256 yieldRate;
        /// @notice Start timestamp of the current yield period
        uint256 periodStart;
        /// @notice End timestamp of the current yield period
        uint256 periodFinish;
        /// @notice Timestamp of the last yield update used to calculate the earned yield
        uint256 lastUpdateTime;
        /// @notice Indicates whether there's an active yield period
        bool isActive;
    }

    //keccak256(abi.encode(uint256(keccak256("YieldBearingVault.storage.v1")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable
    bytes32 private constant YieldDataStorageLocation =
        0x9a66cc64068466ca9954f77b424b83884332fd82446a2cbd356234cdc6547600;

    function _getYieldDataStorage() internal pure returns (YieldDataStorage storage $) {
        assembly {
            $.slot := YieldDataStorageLocation
        }
    }
    // solhint-enable

    /**
     * @dev Initializes the contract
     */
    //solhint-disable-next-line
    function __YieldBearingVault_init(
        address _underlyingToken,
        string memory _name,
        string memory _symbol
    ) internal onlyInitializing {
        __ERC4626_init(IERC20(_underlyingToken));
        __ERC20_init(_name, _symbol);
        __YieldBearingVault_init_unchained();
    }

    /**
     * @dev Initializes the contract
     */
    //solhint-disable-next-line
    function __YieldBearingVault_init_unchained() internal onlyInitializing {
        YieldDataStorage storage $ = _getYieldDataStorage();
        $.totalDeposits = 0;
    }

    /**
     * @dev Calculates total assets available to holders in the vault, including accrued yield and excluding fees.
     * @return Total amount of assets, including yield
     */
    function totalAssets() public view override returns (uint256) {
        YieldDataStorage storage $ = _getYieldDataStorage();
        uint256 currentAssets = $.totalDeposits + _calculateEarnedYield();
        return currentAssets;
    }

    /**
     * @dev Internal function to handle deposits, updates yield, then takes assets then mints then updates total deposits
     * @param caller Address initiating the deposit
     * @param receiver Address receiving the minted shares
     * @param assets Amount of assets being deposited
     * @param shares Amount of shares to mint
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        YieldDataStorage storage $ = _getYieldDataStorage();
        // we MUST call it before any vault interactions
        _updateYield();
        super._deposit(caller, receiver, assets, shares);
        $.totalDeposits += assets;
    }

    /**
     * @dev Internal function to handle withdrawals, updates yield, then burns shares, then transfers assets, then updates total deposits
     * @param caller Address initiating the withdrawal
     * @param receiver Address receiving the assets
     * @param owner Address owning the shares
     * @param assets Amount of assets to withdraw
     * @param shares Amount of shares to burn
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        YieldDataStorage storage $ = _getYieldDataStorage();
        _updateYield(); //NOTE: must be called before totalDeposited is incremented to add earned yield to totalDeposited before it is decremented to avoid underflow
        $.totalDeposits -= assets;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev Calculates the amount of yield that has been earned since the last update
     * If yield period is not active returns 0
     * If yield is active calculate the delta since the last update capped at period finish and multiply by the yieldRate
     *
     * @return Amount of earned yield since last update time
     */
    function _calculateEarnedYield() internal view virtual returns (uint256) {
        YieldDataStorage storage $ = _getYieldDataStorage();
        if (!$.isActive) return 0;
        if (block.timestamp <= $.lastUpdateTime) {
            return 0;
        }
        uint256 endTime = Math.min(block.timestamp, $.periodFinish);
        uint256 duration = endTime - $.lastUpdateTime;
        return Math.mulDiv(duration, $.yieldRate, YIELD_PRECISION, Math.Rounding.Floor);
    }

    /**
     * @dev Updates the yield state, by calculating yield earned and adding it to total totalDeposits
     * keeps track of last update time stamp and deactivates update if yield period if finished to save gas
     */
    function _updateYield() internal virtual {
        YieldDataStorage storage $ = _getYieldDataStorage();
        if (!$.isActive) return;

        uint256 newYield = _calculateEarnedYield();
        $.totalDeposits += newYield;

        $.lastUpdateTime = Math.min(block.timestamp, $.periodFinish);
        // if we are at the end of the period, deactivate yield
        if ($.lastUpdateTime >= $.periodFinish) {
            $.isActive = false;
        }
    }

    /**
     * @dev Starts a new yield distribution period
     * @param yieldAmount Amount of yield to distribute over the next period
     * @param startTime Start time of the new yield period
     * @param endTime End time of the new yield period
     */
    function _startYieldDistribution(uint256 yieldAmount, uint256 startTime, uint256 endTime)
        internal
        virtual;
}
