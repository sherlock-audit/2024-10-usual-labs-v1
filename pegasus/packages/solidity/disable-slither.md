# Disable Slither in Code

Slither is a static analysis framework for Solidity smart contracts. It runs a suite of vulnerability detectors, prints visual information about the contract, and provides an API to easily write custom analyses. In our case the tool is used to detect security vulnerabilities in the smart contracts.

The purpose of this document is to explain why sometimes we disable Slither in the code.

The command used to run slither:

`slither . --filter-paths lib,test --exclude naming-convention`

## Disable Slither in a Contract

### Treasury.sol

From Arbitrary is used only in Dao Collateral and Token Contract. It is not a vulnerability to use an arbitrary address in the transferFrom function.

```solidity
Treasury.transferToTreasury(address,uint256) (src/treasury.sol#53-66) uses arbitrary from in transferFrom: require(bool,string)(ILusDAO(daoToken).transferFrom(from,address(this),amount),Transfer failed) (src/treasury.sol#64)
```

Same thing for transferToTreasurySoftSlashing

```
Treasury.transferToTreasurySoftSlashing(address,uint256) (src/treasury.sol#71-85) uses arbitrary from in transferFrom: require(bool,string)(IPlusDAO(daoToken).transferFrom(from,address(this),amount),Transfer failed) (src/treasury.sol#83)
```

### MmftFactory

All the same vulnerabilities, calls inside a loop, in my opinion this isn't a vulnerabilities since we are just checking token balance and symbol.

```
MmftFactory.hasMmftToken(address) (src/mmftFactory.sol#60-67) has external calls inside a loop: IERC20(_mmfts[i]).balanceOf(account) > 0 (src/mmftFactory.sol#62)

MmftFactory.totalUserMmftAmount(address) (src/mmftFactory.sol#82-88) has external calls inside a loop: total += IERC20(_mmfts[i]).balanceOf(account) (src/mmftFactory.sol#85)

MmftFactory.getPairAddressForAmount(address,uint256) (src/mmftFactory.sol#90-101) has external calls inside a loop: IERC20(_mmfts[i]).balanceOf(account) >= amount (src/mmftFactory.sol#96)

MmftFactory.getCurrency(address) (src/mmftFactory.sol#107-128) has external calls inside a loop: IERC20(_mmfts[i]).balanceOf(account) > 0 (src/mmftFactory.sol#109)

MmftFactory.getCurrency(address) (src/mmftFactory.sol#107-128) has external calls inside a loop: symbol = FFTX(_mmfts[i]).symbol() (src/mmftFactory.sol#110)

MmftFactory.getTokenAddressFromSymbol(string) (src/mmftFactory.sol#130-140) has external calls inside a loop: keccak256(bytes)(abi.encodePacked(FFTX(_mmfts[i]).symbol())) == keccak256(bytes)(abi.encodePacked(symbol)) (src/mmftFactory.sol#133-134)
```

### MmftFactory

All the same vulnerabilities, calls inside a loop, in my opinion this isn't a vulnerabilities since we are just checking token balance and symbol.

```
MmftFactory.hasMmftToken(address) (src/mmftFactory.sol#60-67) has external calls inside a loop: IERC20(_mmfts[i]).balanceOf(account) > 0 (src/mmftFactory.sol#62)

MmftFactory.totalUserMmftAmount(address) (src/mmftFactory.sol#82-88) has external calls inside a loop: total += IERC20(_mmfts[i]).balanceOf(account) (src/mmftFactory.sol#85)

MmftFactory.getPairAddressForAmount(address,uint256) (src/mmftFactory.sol#90-101) has external calls inside a loop: IERC20(_mmfts[i]).balanceOf(account) >= amount (src/mmftFactory.sol#96)

MmftFactory.getCurrency(address) (src/mmftFactory.sol#107-128) has external calls inside a loop: IERC20(_mmfts[i]).balanceOf(account) > 0 (src/mmftFactory.sol#109)

MmftFactory.getCurrency(address) (src/mmftFactory.sol#107-128) has external calls inside a loop: symbol = FFTX(_mmfts[i]).symbol() (src/mmftFactory.sol#110)

MmftFactory.getTokenAddressFromSymbol(string) (src/mmftFactory.sol#130-140) has external calls inside a loop: keccak256(bytes)(abi.encodePacked(FFTX(_mmfts[i]).symbol())) == keccak256(bytes)(abi.encodePacked(symbol)) (src/mmftFactory.sol#133-134)
```

### StbcFactory

All the same vulnerabilities, calls inside a loop, in my opinion this isn't a vulnerabilities since we are just checking token balance and symbol.

```
StbcFactory.getCurrency(address) (src/stbcFactory.sol#104-122) has external calls inside a loop: IERC20(_stbcs[i]).balanceOf(account) > 0 (src/stbcFactory.sol#106)

StbcFactory.getCurrency(address) (src/stbcFactory.sol#104-122) has external calls inside a loop: keccak256(bytes)(abi.encodePacked(STBC(_stbcs[i]).symbol())) == keccak256(bytes)(abi.encodePacked(usUSD)) (src/stbcFactory.sol#108-109)

StbcFactory.getCurrency(address) (src/stbcFactory.sol#104-122) has external calls inside a loop: keccak256(bytes)(abi.encodePacked(STBC(_stbcs[i]).symbol())) == keccak256(bytes)(abi.encodePacked(usEUR)) (src/stbcFactory.sol#114-115)

StbcFactory.getUsUSDAddress() (src/stbcFactory.sol#124-134) has external calls inside a loop: keccak256(bytes)(abi.encodePacked(STBC(_stbcs[i]).symbol())) == keccak256(bytes)(abi.encodePacked(usUSD)) (src/stbcFactory.sol#127-128)

StbcFactory.getStbcAddressFromChar(string) (src/stbcFactory.sol#136-147) has external calls inside a loop: actualCurrency = STBC(_stbcs[i]).symbol().charAt(2) (src/stbcFactory.sol#138)

StbcFactory.getStbcAddressFromCryptoSymbol(string) (src/stbcFactory.sol#149-160) has external calls inside a loop: actualCurrency = STBC(_stbcs[i]).symbol().slice(2,STBC(_stbcs[i]).symbol().strlen()) (src/stbcFactory.sol#152-153)

StbcFactory.getStbcAddressFromSymbol(string) (src/stbcFactory.sol#162-172) has external calls inside a loop: keccak256(bytes)(abi.encodePacked(symbol)) == keccak256(bytes)(abi.encodePacked(STBC(_stbcs[i]).symbol())) (src/stbcFactory.sol#165-166)
```

### DaoCollateral

We acknowledge the reentrancy vulnerabilities, we thinks it's due to ERC20 transfer overriding, not a vulnerabilities since we are checking all function return value and using nonReentrant.

```
Reentrancy in DaoCollateral.redeemStableCoinForCrypto(address,uint256) (src/daoCollateral.sol#211-260):
	External calls:
	- require(bool,string)(INftReceiptCrypto(nft).burn(msg.sender,tokenId,amount),daoCollateral: burn failed) (src/daoCollateral.sol#224-226)
	- require(bool,string)(ILusDAO(daoToken).approve(address(treasury),amount),daoCollateral: approve failed) (src/daoCollateral.sol#231-233)
	- treasury.transferToTreasury(msg.sender,amount) (src/daoCollateral.sol#236)
	- IStbc(IStbcFactory(IRegistry(_registry).getStbcFactoryContract()).getStbcAddressFromCryptoSymbol(ERC20(cryptoRedeem).symbol())).burn(msg.sender,amount) (src/daoCollateral.sol#239-242)
	- require(bool,string)(IERC20(cryptoRedeem).transfer(msg.sender,amount),daoCollateral: transfer failed) (src/daoCollateral.sol#244-246)
	- IStbc(IStbcFactory(IRegistry(_registry).getStbcFactoryContract()).getStbcAddressFromCryptoSymbol(ERC20(cryptoRedeem).symbol())).burn(msg.sender,amount) (src/daoCollateral.sol#248-251)
	- require(bool,string)(IERC20(cryptoRedeem).transfer(msg.sender,amount),daoCollateral: transfer failed) (src/daoCollateral.sol#253-255)
	Event emitted after the call(s):
	- RedeemCrypto(amount) (src/daoCollateral.sol#258)
Reentrancy in DaoCollateral.redeemStableCoinForFiat(address,uint256) (src/daoCollateral.sol#95-151):
	External calls:
	- require(bool,string)(INftReceiptFiat(nft).burn(msg.sender,tokenId,amount),daoCollateral: burn failed) (src/daoCollateral.sol#124-126)
	- treasury.transferToTreasury(msg.sender,amount) (src/daoCollateral.sol#133)
	- require(bool,string)(IERC20(mmftToken).transfer(msg.sender,amount),daoCollateral: transferFrom failed) (src/daoCollateral.sol#136-138)
	- IStbc(stbcBurn).burn(msg.sender,amount) (src/daoCollateral.sol#147)
	Event emitted after the call(s):
	- RedeemStableCoin(amount) (src/daoCollateral.sol#149)
Reentrancy in DaoCollateral.swapCryptoForStablecoin(address,uint256) (src/daoCollateral.sol#156-204):
	External calls:
	- require(bool,string)(IERC20(token).transferFrom(msg.sender,address(this),amount),daoCollateral: transfer failed) (src/daoCollateral.sol#180-183)
	- IStbc(IStbcFactory(IRegistry(_registry).getStbcFactoryContract()).getStbcAddressFromCryptoSymbol(ERC20(token).symbol())).mint(msg.sender,amount) (src/daoCollateral.sol#187-190)
	- ILusDAO(daoToken).mint(msg.sender,amount) (src/daoCollateral.sol#196)
	- require(bool,string)(INftReceiptCrypto(nft).mint(msg.sender,amount),daoCollateral: mint failed) (src/daoCollateral.sol#201)
	Event emitted after the call(s):
	- SwapCrypto(amount) (src/daoCollateral.sol#202)
Reentrancy in DaoCollateral.swapSecurityTokenForStableCoin(uint256) (src/daoCollateral.sol#37-89):
	External calls:
	- require(bool,string)(IMmft(mmft).transferFrom(msg.sender,address(this),amount),daoCollateral: transferFrom failed) (src/daoCollateral.sol#61-64)
	- IStbc(token).mint(msg.sender,amount) (src/daoCollateral.sol#75)
	- ILusDAO(daoToken).mint(msg.sender,amount) (src/daoCollateral.sol#80)
	- require(bool,string)(INftReceiptFiat(nft).mint(msg.sender,amount),daoCollateral: mint failed) (src/daoCollateral.sol#85)
	Event emitted after the call(s):
	- SwapSecurityToken(amount) (src/daoCollateral.sol#87)
Reentrancy in Treasury.transferToTreasury(address,uint256) (src/treasury.sol#51-63):
	External calls:
	- require(bool,string)(ILusDAO(daoToken).transferFrom(from,address(this),amount),Transfer failed) (src/treasury.sol#61)
	Event emitted after the call(s):
	- TransferToTreasury(from,amount) (src/treasury.sol#62)
Reentrancy in Treasury.transferToTreasurySoftSlashing(address,uint256) (src/treasury.sol#67-80):
	External calls:
	- require(bool,string)(IPlusDAO(daoToken).transferFrom(from,address(this),amount),Transfer failed) (src/treasury.sol#78)
	Event emitted after the call(s):
	- TransferToTreasury(from,amount) (src/treasury.sol#79)
Reentrancy in Treasury.withdrawFromTreasury(address,uint256) (src/treasury.sol#82-88):
	External calls:
	- require(bool,string)(ILusDAO(daoToken).transfer(to,amount),Transfer failed) (src/treasury.sol#86)
	Event emitted after the call(s):
	- WithdrawFromTreasury(to,amount) (src/treasury.sol#87)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-3
```
