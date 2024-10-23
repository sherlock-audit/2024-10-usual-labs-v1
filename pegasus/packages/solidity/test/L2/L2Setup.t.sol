// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";

import {L2Usd0} from "src/L2/token/L2Usd0.sol";
import {TokenMapping} from "src/TokenMapping.sol";
import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";

import {SigUtils} from "test/utils/sigUtils.sol";

import {L2Usd0PP} from "src/L2/token/L2Usd0PP.sol";
import {SigUtils} from "test/utils/sigUtils.sol";
import {
    CONTRACT_USD0PP,
    CONTRACT_REGISTRY_ACCESS,
    USD0_BURN,
    USD0_MINT,
    USUALS_BURN,
    USUAL_BURN,
    BLACKLIST_ROLE,
    USUAL_MINT,
    INTENT_MATCHING_ROLE,
    DAO_COLLATERAL,
    CONTRACT_USD0PP,
    CONTRACT_USUALS,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_AIRDROP_DISTRIBUTION,
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
    ONE_WEEK
} from "src/constants.sol";
import {
    DETERMINISTIC_DEPLOYMENT_PROXY,
    CONTRACT_RWA_FACTORY,
    ORACLE_UPDATER,
    REGISTRY_SALT,
    USD0Symbol,
    USD0Name,
    USDPPSymbol,
    USDPPName
} from "src/mock/constants.sol";
import {Normalize} from "src/utils/normalize.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// solhint-disable-next-line max-states-count

contract L2SetupTest is Test {
    RegistryAccess public registryAccess;
    RegistryContract public registryContract;

    L2Usd0 public stbcToken;

    L2Usd0PP public usd0PP;
    TokenMapping public tokenMapping;

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
    address public usual = vm.addr(0x40);
    address public hashnote = vm.addr(0x50);
    address public treasury = vm.addr(0x60);
    address public usdInsurance = vm.addr(0x70);
    address public pegMaintainer = vm.addr(0x80);
    address public blacklistOperator = vm.addr(0x158);

    function setUp() public virtual {
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
        vm.label(jack, "jack");
        vm.label(admin, "admin");
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

        vm.prank(admin);
        registryAccess.grantRole(BLACKLIST_ROLE, blacklistOperator);

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

        // TokenMapping
        tokenMapping = new TokenMapping();
        _resetInitializerImplementation(address(tokenMapping));
        tokenMapping.initialize(address(registryAccess), address(registryContract));
        registryContract.setContract(CONTRACT_TOKEN_MAPPING, address(tokenMapping));

        // USD0
        stbcToken = new L2Usd0();
        _resetInitializerImplementation(address(stbcToken));
        stbcToken.initialize(address(registryContract), USD0Name, USD0Symbol);
        registryContract.setContract(CONTRACT_USD0, address(stbcToken));

        // USD0PP
        usd0PP = new L2Usd0PP();
        _resetInitializerImplementation(address(usd0PP));
        usd0PP.initialize(address(registryContract), USDPPName, USDPPSymbol);
        registryContract.setContract(CONTRACT_USD0PP, address(usd0PP));
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

    function _resetInitializerImplementation(address implementation) internal {
        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 INITIALIZABLE_STORAGE =
            0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        // Set the storage slot to uninitialized
        vm.store(address(implementation), INITIALIZABLE_STORAGE, 0);
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
}
