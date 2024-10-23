// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";

import {Usd0} from "src/token/Usd0.sol";
import {Usd0PPHarness} from "src/mock/token/Usd0PPHarness.sol";
import {UsualS} from "src/token/UsualS.sol";
import {UsualSP} from "src/token/UsualSP.sol";

import {Usd0Harness} from "src/mock/token/Usd0Harness.sol";
import {Usual} from "src/token/Usual.sol";
import {SwapperEngine} from "src/swapperEngine/SwapperEngine.sol";
import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";
import {TokenMapping} from "src/TokenMapping.sol";
import {AirdropTaxCollector} from "src/airdrop/AirdropTaxCollector.sol";
import {AirdropDistribution} from "src/airdrop/AirdropDistribution.sol";

import {DistributionModule} from "src/distribution/DistributionModule.sol";
import {RwaFactoryMock} from "src/mock/rwaFactoryMock.sol";
import {IUsd0PP} from "src/interfaces/token/IUsd0PP.sol";
import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {UsualX} from "src/vaults/UsualX.sol";

import {ClassicalOracle} from "src/oracles/ClassicalOracle.sol";
import {UsualOracle} from "src/oracles/UsualOracle.sol";
import {DataPublisher} from "src/mock/dataPublisher.sol";
import {MockAggregator} from "src/mock/MockAggregator.sol";

import {SigUtils} from "test/utils/sigUtils.sol";

import {ERC20Whitelist} from "src/mock/ERC20Whitelist.sol";
import {USDC} from "src/mock/constants.sol";
import {IRwaMock} from "src/interfaces/token/IRwaMock.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {SigUtils} from "test/utils/sigUtils.sol";
import {
    CONTRACT_USD0PP,
    CONTRACT_REGISTRY_ACCESS,
    USD0_BURN,
    USD0_MINT,
    USUALS_BURN,
    USUAL_BURN,
    USUAL_MINT,
    INTENT_MATCHING_ROLE,
    DAO_COLLATERAL,
    USUALSP,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    CONTRACT_USD0PP,
    CONTRACT_USUALS,
    CONTRACT_USUALSP,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_AIRDROP_DISTRIBUTION,
    CONTRACT_DISTRIBUTION_MODULE,
    CONTRACT_DAO_COLLATERAL,
    CONTRACT_ORACLE,
    CONTRACT_DATA_PUBLISHER,
    CONTRACT_TREASURY,
    CONTRACT_TOKEN_MAPPING,
    CONTRACT_USD0,
    CONTRACT_USUAL,
    CONTRACT_USDC,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_ORACLE_USUAL,
    CONTRACT_ORACLE_USUAL,
    ONE_WEEK,
    AIRDROP_OPERATOR_ROLE,
    AIRDROP_PENALTY_OPERATOR_ROLE,
    PAUSING_CONTRACTS_ROLE,
    ONE_MONTH,
    ONE_YEAR,
    VESTING_DURATION_THREE_YEARS,
    USUALSName,
    USUALSSymbol,
    PAUSING_CONTRACTS_ROLE,
    BLACKLIST_ROLE,
    USUALSP_OPERATOR_ROLE,
    DISTRIBUTION_ALLOCATOR_ROLE,
    DISTRIBUTION_OPERATOR_ROLE,
    DISTRIBUTION_CHALLENGER_ROLE,
    FLOOR_PRICE_UPDATER_ROLE,
    WITHDRAW_FEE_UPDATER_ROLE,
    CONTRACT_USUALX,
    RATE0,
    USUALSymbol,
    USUALName,
    USUALXSymbol,
    USUALXName,
    USUALX_WITHDRAW_FEE
} from "src/constants.sol";
import {
    DETERMINISTIC_DEPLOYMENT_PROXY,
    CONTRACT_RWA_FACTORY,
    ORACLE_UPDATER,
    REGISTRY_SALT,
    USD0Symbol,
    USD0Name,
    ONE_MONTH_IN_SECONDS,
    REDEEM_FEE
} from "src/mock/constants.sol";
import {Normalize} from "src/utils/normalize.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// solhint-disable-next-line max-states-count

contract SetupTest is Test {
    RegistryAccess public registryAccess;
    RegistryContract public registryContract;

    SwapperEngine public swapperEngine;
    DaoCollateral public daoCollateral;

    UsualX public usualX;

    RwaFactoryMock public rwaFactory;
    Usd0 public stbcToken;
    UsualS public usualS;
    UsualSP public usualSP;
    Usual public usualToken;
    IUsd0PP public usd0PP;
    TokenMapping public tokenMapping;
    AirdropDistribution public airdropDistribution;
    DistributionModule public distributionModule;
    ClassicalOracle public classicalOracle;
    AirdropTaxCollector public airdropTaxCollector;
    UsualOracle public usualOracle;
    DataPublisher public dataPublisher;

    uint256 public constant ONE_BPS = 0.0001e18;
    uint256 public constant ONE_PERCENT = 0.01e18;
    uint256 public constant ONE_AND_HALF_PERCENT = 0.015e18;

    address payable public taker;
    address payable public seller;
    address public usualOrg;

    event Received(address, uint256);
    event Upgraded(address indexed implementation);
    event Initialized(uint8 version);

    error InvalidPrice();
    error AmountTooBig();
    error WrongTokenId();
    error NotEnoughCollateral();
    error NullContract();
    error NullAddress();
    error NotAuthorized();
    error ParameterError();
    error AmountIsZero();
    error IncorrectSetting();
    error InsufficientBalance();
    error IncorrectNFTType();
    error InvalidName();
    error InvalidSymbol();
    error Invalid();
    error AlreadyExist();
    error InvalidToken();
    error TokenNotFound();
    error NoCollateral();
    error DeadlineNotPassed();
    error InvalidMask();
    error InvalidIndex();
    error DeadlineNotSet();
    error DeadlineInPast();
    error WrongToken();
    error NotEnoughDeposit();
    error HaveNoRwaToken();
    error NotWhitelisted();
    error AlreadyWhitelisted();
    error NotNFTOwner();
    error InvalidId();
    error ZeroAddress();
    error Blacklisted();
    error SwapMustNotBePaused();

    uint256 public alicePrivKey = 0x1011;
    address public alice = vm.addr(alicePrivKey);
    uint256 public bobPrivKey = 0x2042;
    address public bob = vm.addr(bobPrivKey);
    uint256 public carolPrivKey = 0x3042;
    address public carol = vm.addr(carolPrivKey);
    uint256 public davidPrivKey = 0x4042;
    address public david = vm.addr(davidPrivKey);
    uint256 public jackPrivKey = 0x5042;
    address public jack = vm.addr(jackPrivKey);

    address public admin = vm.addr(0x30);
    address public pauser = vm.addr(0x90);
    address public airdropOperator = vm.addr(0x100);
    address public airdropPenaltyOperator = vm.addr(0x101);
    address public usualSPOperator = vm.addr(0x102);
    address public blacklistOperator = vm.addr(0x103);
    address public floorPriceUpdater = vm.addr(0x104);
    address public withdrawFeeUpdater = vm.addr(0x105);

    address public distributionAllocator = vm.addr(0x201);
    address public distributionOperator = vm.addr(0x202);
    address public distributionChallenger = vm.addr(0x203);

    address public distributionUsualX = vm.addr(0x308);

    address public usual = vm.addr(0x40);
    address public hashnote = vm.addr(0x50);
    address public treasury = vm.addr(0x60);
    address public usdInsurance = vm.addr(0x70);
    address public pegMaintainer = vm.addr(0x80);

    function setUp() public virtual {
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
        vm.label(jack, "jack");
        vm.label(admin, "admin");
        vm.label(pauser, "pauser");
        vm.label(distributionAllocator, "distributionAllocator");
        vm.label(airdropOperator, "airdropOperator");
        vm.label(airdropPenaltyOperator, "airdropPenaltyOperator");
        vm.label(usualSPOperator, "usualSPOperator");
        vm.label(blacklistOperator, "blacklistOperator");
        vm.label(floorPriceUpdater, "floorPriceUpdater");
        vm.label(withdrawFeeUpdater, "withdrawFeeUpdater");
        vm.label(usual, "usual");
        vm.label(treasury, "treasury");
        vm.label(usdInsurance, "usdInsurance");
        vm.label(hashnote, "hashnote");

        address computedRegAccessAddress =
            _computeAddress(REGISTRY_SALT, type(RegistryAccess).creationCode, address(admin));
        registryAccess = RegistryAccess(computedRegAccessAddress);

        // RegistryAccess
        if (computedRegAccessAddress.code.length == 0) {
            registryAccess = new RegistryAccess{salt: REGISTRY_SALT}();
            _resetInitializerImplementation(address(registryAccess));
            registryAccess.initialize(address(admin));
        }

        // RegistryAccess
        vm.startPrank(admin);
        address accessRegistry = address(registryAccess);

        address computedRegContractAddress =
            _computeAddress(REGISTRY_SALT, type(RegistryContract).creationCode, accessRegistry);
        registryContract = RegistryContract(computedRegContractAddress);

        // RegistryContract
        if (computedRegContractAddress.code.length == 0) {
            registryContract = new RegistryContract{salt: REGISTRY_SALT}();
            _resetInitializerImplementation(address(registryContract));
            registryContract.initialize(address(accessRegistry));
        }

        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));

        // Setup USDC in registryContract and registryAccess
        registryContract.setContract(CONTRACT_USDC, address(USDC));

        // Usual
        usualToken = new Usual();
        _resetInitializerImplementation(address(usualToken));
        usualToken.initialize(address(registryContract), USUALName, USUALSymbol);
        registryContract.setContract(CONTRACT_USUAL, address(usualToken));

        usualX = new UsualX();
        _resetInitializerImplementation(address(usualX));
        usualX.initialize(address(registryContract), USUALX_WITHDRAW_FEE, USUALXName, USUALXSymbol);
        registryContract.setContract(CONTRACT_USUALX, address(usualX));

        // TokenMapping
        tokenMapping = new TokenMapping();
        _resetInitializerImplementation(address(tokenMapping));
        tokenMapping.initialize(address(registryAccess), address(registryContract));
        registryContract.setContract(CONTRACT_TOKEN_MAPPING, address(tokenMapping));

        // treasury
        registryContract.setContract(CONTRACT_TREASURY, treasury);

        // oracle
        classicalOracle = new ClassicalOracle();
        _resetInitializerImplementation(address(classicalOracle));
        classicalOracle.initialize(address(registryContract));
        registryContract.setContract(CONTRACT_ORACLE, address(classicalOracle));
        dataPublisher = new DataPublisher(address(registryContract));
        registryContract.setContract(CONTRACT_DATA_PUBLISHER, address(dataPublisher));
        usualOracle = new UsualOracle();
        _resetInitializerImplementation(address(usualOracle));
        usualOracle.initialize(address(registryContract));
        registryContract.setContract(CONTRACT_ORACLE_USUAL, address(usualOracle));

        // USD0
        stbcToken = Usd0(new Usd0Harness());
        _resetInitializerImplementation(address(stbcToken));
        Usd0Harness(address(stbcToken)).initialize(address(registryContract), USD0Name, USD0Symbol);
        Usd0Harness(address(stbcToken)).initializeV1(registryContract);
        Usd0(address(stbcToken)).initializeV2();
        registryContract.setContract(CONTRACT_USD0, address(stbcToken));

        // Swapper Engine
        swapperEngine = new SwapperEngine();
        _resetInitializerImplementation(address(swapperEngine));
        swapperEngine.initialize(address(registryContract));
        registryContract.setContract(CONTRACT_SWAPPER_ENGINE, address(swapperEngine));

        // DaoCollateral
        daoCollateral = new DaoCollateral();
        _resetInitializerImplementation(address(daoCollateral));
        daoCollateral.initialize(address(registryContract), REDEEM_FEE);
        registryContract.setContract(CONTRACT_DAO_COLLATERAL, address(daoCollateral));

        // UsualS
        usualS = new UsualS();
        _resetInitializerImplementation(address(usualS));
        usualS.initialize(IRegistryContract(registryContract), USUALSName, USUALSSymbol);
        registryContract.setContract(CONTRACT_USUALS, address(usualS));

        // UsualSP
        usualSP = new UsualSP();
        _resetInitializerImplementation(address(usualSP));
        usualSP.initialize(address(registryContract), block.timestamp, VESTING_DURATION_THREE_YEARS);
        registryContract.setContract(CONTRACT_USUALSP, address(usualSP));

        // rwa factory
        rwaFactory = new RwaFactoryMock(address(registryContract));
        registryContract.setContract(CONTRACT_RWA_FACTORY, address(rwaFactory));

        // USD0++
        Usd0PPHarness bond = new Usd0PPHarness();
        _resetInitializerImplementation(address(bond));
        bond.initialize(address(registryContract), "Bond", "BND", block.timestamp);
        bond.initializeV1();
        usd0PP = IUsd0PP(address(bond));
        registryContract.setContract(CONTRACT_USD0PP, address(usd0PP));

        // AirDropTaxCollector
        airdropTaxCollector = new AirdropTaxCollector();
        _resetInitializerImplementation(address(airdropTaxCollector));
        airdropTaxCollector.initialize(address(registryContract));
        registryContract.setContract(CONTRACT_AIRDROP_TAX_COLLECTOR, address(airdropTaxCollector));

        // AirdropDistribution
        airdropDistribution = new AirdropDistribution();
        _resetInitializerImplementation(address(airdropDistribution));
        airdropDistribution.initialize(address(registryContract));
        registryContract.setContract(CONTRACT_AIRDROP_DISTRIBUTION, address(airdropDistribution));

        // DistributionModule
        distributionModule = new DistributionModule();
        _resetInitializerImplementation(address(distributionModule));
        distributionModule.initialize(IRegistryContract(registryContract), RATE0);
        registryContract.setContract(CONTRACT_DISTRIBUTION_MODULE, address(distributionModule));
        registryAccess.grantRole(USUAL_MINT, address(distributionModule));

        // add roles
        registryAccess.grantRole(DAO_COLLATERAL, address(daoCollateral));
        registryAccess.grantRole(USUALSP, address(usualSP));
        registryAccess.grantRole(USD0_MINT, address(daoCollateral));
        registryAccess.grantRole(USD0_MINT, treasury);
        registryAccess.grantRole(USD0_BURN, address(daoCollateral));
        registryAccess.grantRole(USUALS_BURN, address(admin));
        registryAccess.grantRole(USUAL_MINT, admin);
        registryAccess.grantRole(USUAL_MINT, address(airdropDistribution));
        registryAccess.grantRole(USUAL_BURN, admin);
        registryAccess.grantRole(USUAL_BURN, address(usualX));
        registryAccess.grantRole(AIRDROP_OPERATOR_ROLE, airdropOperator);
        registryAccess.grantRole(AIRDROP_PENALTY_OPERATOR_ROLE, airdropPenaltyOperator);
        registryAccess.grantRole(USUALSP_OPERATOR_ROLE, usualSPOperator);
        registryAccess.grantRole(BLACKLIST_ROLE, blacklistOperator);
        registryAccess.grantRole(WITHDRAW_FEE_UPDATER_ROLE, withdrawFeeUpdater);
        //Ensure all relevant addresses can intent match
        registryAccess.grantRole(INTENT_MATCHING_ROLE, admin);
        registryAccess.grantRole(INTENT_MATCHING_ROLE, address(alice));
        registryAccess.grantRole(PAUSING_CONTRACTS_ROLE, address(pauser));
        registryAccess.grantRole(DISTRIBUTION_ALLOCATOR_ROLE, distributionAllocator);
        registryAccess.grantRole(DISTRIBUTION_OPERATOR_ROLE, distributionOperator);
        registryAccess.grantRole(DISTRIBUTION_CHALLENGER_ROLE, distributionChallenger);
        registryAccess.grantRole(FLOOR_PRICE_UPDATER_ROLE, floorPriceUpdater);
        vm.stopPrank();
    }

    function _computeAddress(bytes32 salt, bytes memory _code, address _usual)
        internal
        pure
        returns (address addr)
    {
        bytes memory bytecode = abi.encodePacked(_code, abi.encode(_usual));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), DETERMINISTIC_DEPLOYMENT_PROXY, salt, keccak256(bytecode)
            )
        );
        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    function _setupBucket(address rwa, address USD0) internal {
        vm.startPrank(address(admin));
        registryAccess.grantRole(ORACLE_UPDATER, usual);
        registryAccess.grantRole(ORACLE_UPDATER, hashnote);
        vm.stopPrank();
        _initializeOracleFeed(usual, address(USD0), 1e18, true);

        if (!tokenMapping.isUsd0Collateral(rwa)) {
            vm.prank(admin);
            tokenMapping.addUsd0Rwa(rwa);
        }
        // treasury allow max uint256 to daoCollateral
        vm.prank(treasury);
        ERC20(rwa).approve(address(daoCollateral), type(uint256).max);
    }

    function _setupBucket(address rwa) internal {
        _setupBucket(rwa, address(stbcToken));
    }

    function _initializeOracleFeed(address caller, address token, int256 price, bool stable)
        internal
    {
        vm.prank(caller);
        dataPublisher.publishData(token, price);
        skip(1);
        vm.prank(caller);
        dataPublisher.publishData(token, price);
        vm.prank(admin);
        usualOracle.initializeTokenOracle(token, 1 days, stable);
    }

    function whitelistPublisher(address rwa, address USD0) public {
        vm.startPrank(admin);
        if (!dataPublisher.isWhitelistPublisher(rwa, hashnote)) {
            dataPublisher.addWhitelistPublisher(rwa, hashnote);
        }
        if (!dataPublisher.isWhitelistPublisher(USD0, usual)) {
            dataPublisher.addWhitelistPublisher(USD0, usual);
        }
        require(dataPublisher.isWhitelistPublisher(USD0, usual), "not whitelisted");
        vm.stopPrank();
    }

    function testSetup() public view {
        assertEq(address(registryAccess), registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
    }

    function _getNonce(address token, address owner) internal view returns (uint256) {
        return IERC20Permit(token).nonces(owner);
    }

    function _getSelfPermitData(
        address token,
        address owner,
        uint256 ownerPrivateKey,
        address spender,
        uint256 amount,
        uint256 deadline
    ) internal returns (uint8, bytes32, bytes32) {
        uint256 nonce = _getNonce(token, owner);
        return _signPermitData(
            token, _getPermitData(owner, spender, amount, deadline, nonce), ownerPrivateKey
        );
    }

    function _getPermitData(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint256 nonce
    ) internal pure returns (SigUtils.Permit memory permit) {
        permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: amount,
            nonce: nonce,
            deadline: deadline
        });
    }

    function _signPermitData(address token, SigUtils.Permit memory permit, uint256 ownerPrivateKey)
        internal
        returns (uint8, bytes32, bytes32)
    {
        IERC20Permit ercPermit = IERC20Permit(token);
        SigUtils sigUtils = new SigUtils(ercPermit.DOMAIN_SEPARATOR());
        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return (v, r, s);
    }

    function _getSelfPermitData(
        address token,
        address owner,
        uint256 ownerPrivateKey,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint256 nonce
    ) internal returns (uint8, bytes32, bytes32) {
        return _signPermitData(
            token, _getPermitData(owner, spender, amount, deadline, nonce), ownerPrivateKey
        );
    }

    function _setOraclePrice(address token, uint256 amount) internal {
        MockAggregator dataSource = new MockAggregator(token, int256(amount), 1);

        vm.prank(admin);
        classicalOracle.initializeTokenOracle(token, address(dataSource), ONE_WEEK, false);

        amount = Normalize.tokenAmountToWad(amount, uint8(dataSource.decimals()));
        assertEq(classicalOracle.getPrice(address(token)), amount);
    }

    function _getTenPercent(uint256 amount) internal pure returns (uint256) {
        return amount * 1000 / 10_000;
    }

    function _getDotFivePercent(uint256 amount) internal pure returns (uint256) {
        return amount * 500 / 100_000;
    }

    function _getDotOnePercent(uint256 amount) internal pure returns (uint256) {
        return amount * 100 / 100_000;
    }

    function _getAmountMinusFeeInUSD(uint256 amount, address collateralToken)
        internal
        view
        returns (uint256)
    {
        // get amount in USD
        uint256 amountInUSD = classicalOracle.getQuote(collateralToken, amount);

        // take 0.1% fee on USD
        uint256 fee = _getDotOnePercent(amountInUSD);

        return amount - fee;
    }

    function _whitelistRWA(address rwa, address user) internal {
        vm.startPrank(address(admin));
        // check if user is whitelisted
        if (!ERC20Whitelist(rwa).isWhitelisted(user)) {
            // user needs to be whitelisted
            ERC20Whitelist(rwa).whitelist(user);
        }
        vm.stopPrank();
    }

    function _linkSTBCToRwa(IRwaMock rwa) internal {
        if (!tokenMapping.isUsd0Collateral(address(rwa))) {
            vm.prank(admin);
            tokenMapping.addUsd0Rwa(address(rwa));
        }
    }

    function _createBond(string memory name, string memory symbol) internal returns (Usd0PP) {
        vm.startPrank(address(admin));
        Usd0PPHarness newUsd0PPaddr = new Usd0PPHarness();
        _resetInitializerImplementation(address(newUsd0PPaddr));
        newUsd0PPaddr.initialize(address(registryContract), name, symbol, block.timestamp);
        newUsd0PPaddr.initializeV1();

        registryContract.setContract(CONTRACT_USD0PP, address(newUsd0PPaddr));
        vm.stopPrank();
        return newUsd0PPaddr;
    }

    function _resetInitializerImplementation(address implementation) internal {
        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 INITIALIZABLE_STORAGE =
            0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        // Set the storage slot to uninitialized
        vm.store(address(implementation), INITIALIZABLE_STORAGE, 0);
    }
}
