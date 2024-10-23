// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

/* Roles */
bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
bytes32 constant PAUSING_CONTRACTS_ROLE = keccak256("PAUSING_CONTRACTS_ROLE");
bytes32 constant EARLY_BOND_UNLOCK_ROLE = keccak256("EARLY_BOND_UNLOCK_ROLE");
bytes32 constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");
bytes32 constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
bytes32 constant WITHDRAW_FEE_UPDATER_ROLE = keccak256("WITHDRAW_FEE_UPDATER_ROLE");
bytes32 constant FLOOR_PRICE_UPDATER_ROLE = keccak256("FLOOR_PRICE_UPDATER_ROLE");
bytes32 constant DAO_COLLATERAL = keccak256("DAO_COLLATERAL_CONTRACT");
bytes32 constant USUALSP = keccak256("USUALSP_CONTRACT");
bytes32 constant USD0_MINT = keccak256("USD0_MINT");
bytes32 constant USD0_BURN = keccak256("USD0_BURN");
bytes32 constant USD0PP_MINT = keccak256("USD0PP_MINT");
bytes32 constant USD0PP_BURN = keccak256("USD0PP_BURN");
bytes32 constant USUALS_BURN = keccak256("USUALS_BURN");
bytes32 constant USUAL_MINT = keccak256("USUAL_MINT");
bytes32 constant USUAL_BURN = keccak256("USUAL_BURN");
bytes32 constant INTENT_MATCHING_ROLE = keccak256("INTENT_MATCHING_ROLE");
bytes32 constant NONCE_THRESHOLD_SETTER_ROLE = keccak256("NONCE_THRESHOLD_SETTER_ROLE");
bytes32 constant PEG_MAINTAINER_ROLE = keccak256("PEG_MAINTAINER_ROLE");
bytes32 constant SWAPPER_ENGINE = keccak256("SWAPPER_ENGINE");
bytes32 constant INTENT_TYPE_HASH = keccak256(
    "SwapIntent(address recipient,address rwaToken,uint256 amountInTokenDecimals,uint256 nonce,uint256 deadline)"
);
bytes32 constant DISTRIBUTION_ALLOCATOR_ROLE = keccak256("DISTRIBUTION_ALLOCATOR_ROLE");
bytes32 constant DISTRIBUTION_OPERATOR_ROLE = keccak256("DISTRIBUTION_OPERATOR_ROLE");
bytes32 constant DISTRIBUTION_CHALLENGER_ROLE = keccak256("DISTRIBUTION_CHALLENGER_ROLE");
/* Airdrop Roles */
bytes32 constant AIRDROP_OPERATOR_ROLE = keccak256("AIRDROP_OPERATOR_ROLE");
bytes32 constant AIRDROP_PENALTY_OPERATOR_ROLE = keccak256("AIRDROP_PENALTY_OPERATOR_ROLE");
bytes32 constant USUALSP_OPERATOR_ROLE = keccak256("USUALSP_OPERATOR_ROLE");

/* Contracts */
bytes32 constant CONTRACT_REGISTRY_ACCESS = keccak256("CONTRACT_REGISTRY_ACCESS");
bytes32 constant CONTRACT_DAO_COLLATERAL = keccak256("CONTRACT_DAO_COLLATERAL");
bytes32 constant CONTRACT_USD0PP = keccak256("CONTRACT_USD0PP");
bytes32 constant CONTRACT_USUALS = keccak256("CONTRACT_USUALS");
bytes32 constant CONTRACT_USUALSP = keccak256("CONTRACT_USUALSP");
bytes32 constant CONTRACT_TOKEN_MAPPING = keccak256("CONTRACT_TOKEN_MAPPING");
bytes32 constant CONTRACT_ORACLE = keccak256("CONTRACT_ORACLE");
bytes32 constant CONTRACT_ORACLE_USUAL = keccak256("CONTRACT_ORACLE_USUAL");
bytes32 constant CONTRACT_DATA_PUBLISHER = keccak256("CONTRACT_DATA_PUBLISHER");
bytes32 constant CONTRACT_TREASURY = keccak256("CONTRACT_TREASURY");
bytes32 constant CONTRACT_SWAPPER_ENGINE = keccak256("CONTRACT_SWAPPER_ENGINE");
bytes32 constant CONTRACT_AIRDROP_DISTRIBUTION = keccak256("CONTRACT_AIRDROP_DISTRIBUTION");
bytes32 constant CONTRACT_AIRDROP_TAX_COLLECTOR = keccak256("CONTRACT_AIRDROP_TAX_COLLECTOR");
bytes32 constant CONTRACT_DISTRIBUTION_MODULE = keccak256("CONTRACT_DISTRIBUTION_MODULE");

/* Contract tokens */
bytes32 constant CONTRACT_USD0 = keccak256("CONTRACT_USD0");
bytes32 constant CONTRACT_USUAL = keccak256("CONTRACT_USUAL");
bytes32 constant CONTRACT_USDC = keccak256("CONTRACT_USDC");
bytes32 constant CONTRACT_USUALX = keccak256("CONTRACT_USUALX");

/* Token names and symbols */
string constant USUALSSymbol = "USUAL*";
string constant USUALSName = "USUAL Star";

string constant USUALSymbol = "USUAL";
string constant USUALName = "USUAL";

string constant USUALXSymbol = "USUALX";
string constant USUALXName = "USUALX";

/* Constants */
uint256 constant SCALAR_ONE = 1e18;
uint256 constant BPS_SCALAR = 10_000; // 10000 basis points = 100%
uint256 constant DISTRIBUTION_FREQUENCY_SCALAR = 1 days;

uint256 constant SCALAR_TEN_KWEI = 10_000;
uint256 constant MAX_REDEEM_FEE = 2500;
uint256 constant MINIMUM_USDC_PROVIDED = 100e6; //minimum of 100 USDC deposit;
// we take 12sec as the average block time
// 1 year = 3600sec * 24 hours * 365 days * 4 years  = 126_144_000 + 1 day // adding a leap day
uint256 constant BOND_DURATION_FOUR_YEAR = 126_230_400; //including a leap day;
uint256 constant USUAL_DISTRIBUTION_CHALLENGE_PERIOD = 1 weeks;
uint256 constant BASIS_POINT_BASE = 10_000;

uint256 constant VESTING_DURATION_THREE_YEARS = 94_608_000; // 3 years
uint256 constant USUALSP_VESTING_STARTING_DATE = 1_731_412_800; // November 12th 12H GMT: 1731412800

uint256 constant AIRDROP_INITIAL_START_TIME = 1_734_004_800; // Dec 12 2024 12:00:00 GMT+0000
uint256 constant AIRDROP_VESTING_DURATION_IN_MONTHS = 6;
uint256 constant ONE_YEAR = 31_536_000; // 365 days
uint256 constant SIX_MONTHS = 15_768_000;
uint256 constant ONE_MONTH = 2_628_000; // ONE_YEAR / 12 = 30,4 days
uint64 constant ONE_WEEK = 604_800;
uint256 constant NUMBER_OF_MONTHS_IN_THREE_YEARS = 36;
uint256 constant END_OF_EARLY_UNLOCK_PERIOD = 1_735_686_000; // 31st Dec 2024 23:00:00 GMT+0000
uint256 constant FIRST_AIRDROP_VESTING_CLAIMING_DATE = 1_736_683_200; // 12th Jan 2025 12:00:00 GMT+0000
uint256 constant SECOND_AIRDROP_VESTING_CLAIMING_DATE = 1_739_361_600; // 12th Feb 2025 12:00:00 GMT+0000
uint256 constant THIRD_AIRDROP_VESTING_CLAIMING_DATE = 1_741_780_800; // 12th Mar 2025 12:00:00 GMT+0000
uint256 constant FOURTH_AIRDROP_VESTING_CLAIMING_DATE = 1_744_459_200; // 12th Apr 2025 12:00:00 GMT+0000
uint256 constant FIFTH_AIRDROP_VESTING_CLAIMING_DATE = 1_747_051_200; // 12th May 2025 12:00:00 GMT+0000
uint256 constant SIXTH_AIRDROP_VESTING_CLAIMING_DATE = 1_749_729_600; // 12th Jun 2025 12:00:00 GMT+0000
uint256 constant INITIAL_FLOOR_PRICE = 999_000_000_000_000_000;

/* UsualX initial withdraw fee */
uint256 constant USUALX_WITHDRAW_FEE = 500; // in BPS 5%

/* Usual Distribution Bucket Distribution Shares */
uint256 constant LBT_DISTRIBUTION_SHARE = 4044;
uint256 constant LYT_DISTRIBUTION_SHARE = 2256;
uint256 constant IYT_DISTRIBUTION_SHARE = 400;
uint256 constant BRIBE_DISTRIBUTION_SHARE = 400;
uint256 constant ECO_DISTRIBUTION_SHARE = 250;
uint256 constant DAO_DISTRIBUTION_SHARE = 300;
uint256 constant MARKET_MAKERS_DISTRIBUTION_SHARE = 350;
uint256 constant USUALX_DISTRIBUTION_SHARE = 1000;
uint256 constant USUALSTAR_DISTRIBUTION_SHARE = 1000;

uint256 constant ONE_USDC = 1e6;
uint256 constant MAX_25_PERCENT_WITHDRAW_FEE = 2500; // 25% fee
uint256 constant YIELD_PRECISION = 1 days;

uint256 constant USUALS_TOTAL_SUPPLY = 360_000_000e18;

/* Token Addresses */

address constant USYC = 0x136471a34f6ef19fE571EFFC1CA711fdb8E49f2b;

/*
 * The maximum relative price difference between two oracle responses allowed in order for the PriceFeed
 * to return to using the Oracle oracle. 18-digit precision.
 */

uint256 constant INITIAL_MAX_DEPEG_THRESHOLD = 100;

/* Maximum number of RWA tokens that can be associated with USD0 */
uint256 constant MAX_RWA_COUNT = 10;

/* Curvepool Addresses */
address constant CURVE_POOL_USD0_USD0PP = 0x1d08E7adC263CfC70b1BaBe6dC5Bb339c16Eec52;
int128 constant CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0 = 0;
int128 constant CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0PP = 1;

/* Airdrop */

uint256 constant AIRDROP_CLAIMING_PERIOD_LENGTH = 182 days;

/* Distribution */
uint256 constant RATE0 = 545; // 5.45% in basis points

/* Hexagate */
address constant HEXAGATE_PAUSER = 0x114644925eD9A6Ab20bF85f36F1a458DF181b57B;

/* Mainnet Usual Deployment */
address constant USUAL_MULTISIG_MAINNET = 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7;
address constant USUAL_PROXY_ADMIN_MAINNET = 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16;
address constant REGISTRY_CONTRACT_MAINNET = 0x0594cb5ca47eFE1Ff25C7B8B43E221683B4Db34c;
