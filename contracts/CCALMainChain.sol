/**************************
  ___  ____  ____  ____   ___   ___  ____    ___    
|_  ||_  _||_  _||_  _|.'   `.|_  ||_  _| .'   `.  
  | |_/ /    \ \  / / /  .-.  \ | |_/ /  /  .-.  \ 
  |  __'.     \ \/ /  | |   | | |  __'.  | |   | | 
 _| |  \ \_   _|  |_  \  `-'  /_| |  \ \_\  `-'  / 
|____||____| |______|  `.___.'|____||____|`.___.'  

 **************************/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { ValidateLogic } from "./libs/ValidateLogic.sol";
import { Errors } from "./libs/Errors.sol";

import "./StorageLayer.sol";
import "./BaseContract.sol";

import "./interface.sol";

contract CCALMainChain is
    BaseContract,
    StorageLayer
{
    uint16 public constant BASE_FEE = 10000;

    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    uint public fee;

    address public vault;

    ICreditSystem public creditSystem;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {  
        _disableInitializers();  
    }

    function initialize(
        ICreditSystem _creditSystem,
        address _vault,
        uint _fee,
        uint16 _selfChainId,
        address _endPoint,
        address _currency,
        uint8 _currencyDecimal
    ) external initializer {
        BaseContract.initialize(_endPoint, _selfChainId);
        setFee(_fee);
        setVault(_vault);
        setCreditSystem(_creditSystem);
        toggleTokens(_currency, _currencyDecimal, true, true);
    }

    function setCreditSystem(ICreditSystem _creditSystem) public onlyOwner {
        creditSystem = _creditSystem;
    }

    function setFee(uint _fee) public onlyOwner {
        require(_fee <= 1000, Errors.SET_FEE_TOO_LARGE);
        fee = _fee;
    }

    function setVault(address _vault) public onlyOwner {
        require(_vault != address(0), Errors.SET_VAULT_ADDRESS_INVALID);
        vault = _vault;
    }

    event LogBorrowAsset(address indexed borrower, uint indexed internalId, uint borrowIndex, bool useCredit, uint time);
    function _borrow(address _borrower, uint internalId, bool _useCredit) internal {
        ICCAL.DepositAsset storage asset = nftMap[internalId];

        asset.borrowIndex += 1;
        asset.borrower = _borrower;
        asset.borrowTime = block.timestamp;
        asset.status = ICCAL.AssetStatus.BORROW;

        uint len = asset.toolIds.length;
        for (uint i = 0; i < len;) {
            IERC721Upgradeable(asset.game).safeTransferFrom(address(this), _borrower, asset.toolIds[i]);
            unchecked {
                ++i;
            }
        }

        emit LogBorrowAsset(_borrower, internalId, asset.borrowIndex, _useCredit, asset.borrowTime);
    }

    function borrowAsset(
        uint internalId,
        uint _amountPerDay,
        uint _totalAmount,
        uint _minPay,
        uint _cycle,
        bool _useCredit
    ) external {
        bytes32 freeKey = keccak256(abi.encode(internalId, selfChainId));
        require(freezeMap[freeKey].operator == address(0), Errors.VL_BORROW_ALREADY_FREEZE);

        require(ValidateLogic.checkBorrowPara(
            internalId,
            _amountPerDay,
            _totalAmount,
            _minPay,
            _cycle,
            nftMap
        ), Errors.VL_BORROW_PARAM_NOT_MATCH);

        address _token = nftMap[internalId].token;
        uint amount = nftMap[internalId].totalAmount;

        if (_useCredit) {
            require(tokenInfos[_token].stable, Errors.VL_TOKEN_NOT_MATCH_CREDIT);
            uint8 decimals = tokenInfos[_token].decimals;
            require(this.checkSuitCredit(_msgSender(), amount, decimals), Errors.VL_CREDIT_NOT_VALID);
            creditUsed[_msgSender()] = creditUsed[_msgSender()] + (amount * (uint(1 ether)) / (10**decimals));
        }

        freezeMap[freeKey] = ICCAL.FreezeTokenInfo({
            amount: amount,
            useCredit: _useCredit,
            operator: _msgSender(),
            token: _token
        });

        if (!_useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), address(this), amount);
        }

        _borrow(_msgSender(), internalId, _useCredit);
    }

    function checkSuitCredit(
        address user,
        uint amount,
        uint8 decimals
    ) external returns(bool) {
        bool canBorrow;
        (, bool inCCALSystem) = ICreditSystem(creditSystem).getState(user);
        if (inCCALSystem) {
            uint creditLine = ICreditSystem(creditSystem).getCCALCreditLine(user);
            if (amount * (uint(1 ether)) / (10**decimals) + creditUsed[user] <= creditLine) {
                canBorrow = true;
            }
        }
        return canBorrow;
    }

    function estimateCrossChainBorrowFees(
        uint16 _dstChainId,
        uint internalId,
        uint _amountPerDay,
        uint _totalAmount,
        uint _minPay,
        address _token,
        uint _cycle,
        bool _useCredit
    ) public view returns(uint) {
        // get the fees we need to pay to LayerZero + Relayer to cover message delivery
        // you will be refunded for extra gas paid
        (uint messageFee, ) = layerZeroEndpoint.estimateFees(
            _dstChainId,
            address(this),
            abi.encode(
                ICCAL.Operation.BORROW,
                abi.encode(
                    _msgSender(),
                    internalId,
                    _amountPerDay,
                    _totalAmount,
                    _minPay,
                    _token,
                    _cycle,
                    _useCredit
                )
            ),
            false,
            abi.encodePacked(VERSION, GAS_FOR_DEST_LZ_RECEIVE)
        );

        return messageFee;
    }

    function borrowOtherChainAsset(
        uint16 _dstChainId,
        uint internalId,
        uint _amountPerDay,
        uint _totalAmount,
        uint _minPay,
        address _token,
        uint _cycle,
        bool _useCredit
    ) external payable {
        require(selfChainId != _dstChainId, Errors.LZ_NOT_OTHER_CHAIN);
        bytes32 freeKey = keccak256(abi.encode(internalId, _dstChainId));
        require(freezeMap[freeKey].operator == address(0), Errors.VL_BORROW_ALREADY_FREEZE);

        require(checkTokenInList(_token), Errors.VL_TOKEN_NOT_SUPPORT);

        uint messageFee = estimateCrossChainBorrowFees(
            _dstChainId,
            internalId,
            _amountPerDay,
            _totalAmount,
            _minPay,
            _token,
            _cycle,
            _useCredit
        );

        require(msg.value >= messageFee, Errors.LZ_GAS_TOO_LOW);

        if (_useCredit) {
            require(tokenInfos[_token].stable, Errors.VL_TOKEN_NOT_MATCH_CREDIT);
            uint8 decimals = tokenInfos[_token].decimals;
            require(this.checkSuitCredit(_msgSender(), _totalAmount, decimals), Errors.VL_CREDIT_NOT_VALID);
            creditUsed[_msgSender()] = creditUsed[_msgSender()] + (_totalAmount * (uint(1 ether)) / (10**decimals));
        }

        freezeMap[freeKey] = ICCAL.FreezeTokenInfo({
            amount: _totalAmount,
            useCredit: _useCredit,
            operator: _msgSender(),
            token: _token
        });

        if (!_useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), address(this), _totalAmount);
        }

        layerZeroEndpoint.send{value: msg.value}(
            _dstChainId,                          // destination chainId
            remotes[_dstChainId],                 // destination address of ccal contract
            abi.encode(
                ICCAL.Operation.BORROW,
                abi.encode(
                    _msgSender(),
                    internalId,
                    _amountPerDay,
                    _totalAmount,
                    _minPay,
                    _token,
                    _cycle,
                    _useCredit
                )
            ),                       // abi.encoded()'ed bytes
            payable(_msgSender()),   // refund address
            address(0x0),            // 'zroPaymentAddress' unused for this
            abi.encodePacked(VERSION, GAS_FOR_DEST_LZ_RECEIVE)                       // txParameters 
        );
    }

    event LogRepayAsset(uint indexed internalId, uint interest, uint borrowIndex, uint time);
    function repayAsset(uint internalId) external {
        ICCAL.DepositAsset storage asset = nftMap[internalId];
        require(asset.status == ICCAL.AssetStatus.BORROW && asset.borrower == _msgSender(), Errors.VL_REPAY_CONDITION_NOT_MATCH);

        _afterRepay(internalId);

        uint len = asset.toolIds.length;
        for (uint idx = 0; idx < len;) {
            IERC721Upgradeable(asset.game).safeTransferFrom(_msgSender(), address(this), asset.toolIds[idx]);

            unchecked {
                ++idx;
            }
        }
    }

    function _afterRepay(uint internalId) internal {
        ICCAL.DepositAsset storage asset = nftMap[internalId];

        uint interest = ValidateLogic.calcCost(
            asset.amountPerDay,
            block.timestamp - asset.borrowTime,
            asset.minPay,
            asset.totalAmount
        );

        asset.borrowTime = 0;
        asset.borrower = address(0);
        asset.status = ICCAL.AssetStatus.INITIAL;

        updateDataAfterRepay(asset.holder, internalId, selfChainId, interest, asset.borrowIndex);

        emit LogRepayAsset(internalId, interest, asset.borrowIndex, block.timestamp);
    }

    event LogWithdrawAsset(uint indexed internalId);
    function withdrawAsset(uint internalId) external whenNotPaused {
        ICCAL.DepositAsset memory asset = nftMap[internalId];

        require(
            (asset.status != ICCAL.AssetStatus.WITHDRAW) &&
            (asset.status != ICCAL.AssetStatus.LIQUIDATE) &&
            _msgSender() == asset.holder,
            Errors.VL_WITHDRAW_ASSET_CONDITION_NOT_MATCH
        );

        // if tool isn't borrow, depositor can withdraw
        if (asset.status == ICCAL.AssetStatus.INITIAL) {
            nftMap[internalId].status = ICCAL.AssetStatus.WITHDRAW;

            uint len = asset.toolIds.length;
            for (uint idx = 0; idx < len;) {
                IERC721Upgradeable(asset.game).safeTransferFrom(address(this), _msgSender(), asset.toolIds[idx]);
                unchecked {
                    ++idx;
                }
            }

            emit LogWithdrawAsset(internalId);
        } else {
            require(block.timestamp > asset.depositTime + asset.cycle, Errors.VL_LIQUIDATE_NOT_EXPIRED);
            liquidate(internalId);
        }
    }

    event LogWithdrawToken(bytes _address, uint16 chainId, uint indexed internalId, uint borrowIdx, address indexed user, uint amount);
    function withdrawToken(uint16 _chainId, uint internalId, uint _borrowIdx) external {
        (bool canWithdraw, uint index) = ValidateLogic.checkWithdrawTokenPara(
            _msgSender(),
            _chainId,
            internalId,
            _borrowIdx,
            pendingWithdraw
        );
        require(canWithdraw, Errors.VL_WITHDRAW_TOKEN_PARAM_NOT_MATCH);
        ICCAL.InterestInfo[] storage list = pendingWithdraw[_msgSender()];

        ICCAL.InterestInfo memory item = list[index];

        list[index] = list[list.length - 1];
        list.pop();

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(item.token), _msgSender(), item.amount);

        emit LogWithdrawToken(remotes[_chainId], _chainId, internalId, _borrowIdx, _msgSender(), item.amount);
    }

    event LogLiquidation(uint internalId, uint time);
    function liquidate(uint internalId) internal {

        ICCAL.DepositAsset storage asset = nftMap[internalId];

        asset.status = ICCAL.AssetStatus.LIQUIDATE;

        bytes32 freeKey = keccak256(abi.encode(internalId, selfChainId));

        ICCAL.FreezeTokenInfo memory info = freezeMap[freeKey];
        delete freezeMap[freeKey];

        uint toVault = info.amount * fee / BASE_FEE;
        recordWithdraw(asset.holder, internalId, selfChainId, info.amount - toVault, info.token, asset.borrowIndex);
        if (!info.useCredit) {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), vault, toVault);
        }
        emit LogLiquidation(internalId, block.timestamp);
    }

    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload);
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        // boilerplate: only allow this endpiont to be the caller of lzReceive!
        require(msg.sender == address(layerZeroEndpoint), Errors.LZ_BAD_SENDER);
        // owner must have setRemote() to allow its remote contracts to send to this contract
        require(
            _srcAddress.length == remotes[_srcChainId].length && keccak256(_srcAddress) == keccak256(remotes[_srcChainId]),
            Errors.LZ_BAD_REMOTE_ADDR
        );

        try this._LzReceive(_payload) {
            // do nothing
        } catch {
            // error / exception
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload);
        }
    }

    function _LzReceive(bytes memory _payload) external {
        require(msg.sender == address(this), Errors.LZ_ONLY_BRIDGE);
        // decode
        (ICCAL.Operation op, bytes memory _other) = abi.decode(_payload, (ICCAL.Operation, bytes));
        if (op == ICCAL.Operation.REPAY) {
            handleRepayAsset(_other);
        }
        if (op == ICCAL.Operation.LIQUIDATE) {
            handleLiquidate(_other);
        }
    }

    function recordWithdraw(
        address user,
        uint internalId,
        uint16 _chainId,
        uint amount,
        address token,
        uint borrowIndex
    ) internal {
        pendingWithdraw[user].push(
            ICCAL.InterestInfo({
                borrowIndex: borrowIndex,
                internalId: internalId,
                chainId: _chainId,
                amount: amount,
                token: token
            })
        );
    }

    // only execute on main-chain
    function handleRepayAsset(bytes memory _payload) internal {
        (
            address _holder,
            uint internalId,
            uint16 _chainId,
            uint _interest,
            uint _borrowIndex
        ) = abi.decode(
            _payload,
            (address, uint, uint16, uint, uint)
        );

        updateDataAfterRepay(_holder, internalId, _chainId, _interest, _borrowIndex);
    }

    function updateDataAfterRepay(
        address assetHolder,
        uint internalId,
        uint16 _chainId,
        uint _interest,
        uint _borrowIndex
    ) internal {
        bytes32 freeKey = keccak256(abi.encode(internalId, _chainId));

        ICCAL.FreezeTokenInfo memory info = freezeMap[freeKey];
        delete freezeMap[freeKey];

        uint interest = _interest > info.amount ? info.amount : _interest;

        uint toVault = interest * fee / BASE_FEE;

        recordWithdraw(assetHolder, internalId, _chainId, interest - toVault, info.token, _borrowIndex);

        if (info.useCredit) {
            creditUsed[info.operator] = creditUsed[info.operator] - ((info.amount - interest) * (uint(1 ether)) / (10**tokenInfos[info.token].decimals));
        } else {
            recordWithdraw(info.operator, internalId, _chainId, info.amount - interest, info.token, _borrowIndex);
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), vault, toVault);
        }
    }

    /**
        @dev when liquidate on other-chain, main-chain will sync the freeze info
     */
    function handleLiquidate(bytes memory _payload) internal {
        (
            address _holder,
            uint16 _chainId,
            uint internalId,
            uint _borrowIndex
        ) = abi.decode(
            _payload,
            (address, uint16, uint, uint)
        );

        bytes32 freeKey = keccak256(abi.encode(internalId, _chainId));

        ICCAL.FreezeTokenInfo memory info = freezeMap[freeKey];

        delete freezeMap[freeKey];

        uint toVault = info.amount * fee / BASE_FEE;

        recordWithdraw(_holder, internalId, _chainId, info.amount - toVault, info.token, _borrowIndex);

        if (!info.useCredit) {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), vault, toVault);
        }
    }

    function repayCredit(uint amount, address _token) external {
        require(amount > 0, Errors.VL_REPAY_CREDIT_AMOUNT_0);
        require(checkTokenInList(_token), Errors.VL_TOKEN_NOT_SUPPORT);

        uint _creditUsed = creditUsed[_msgSender()];
        require(_creditUsed > 0, Errors.VL_REPAY_CREDIT_NO_NEED);

        uint8 decimals = tokenInfos[_token].decimals;

        require(
            amount * (uint(1 ether)) / (10**decimals) <= _creditUsed,
            Errors.VL_REPAY_CREDIT_AMOUNT_TOO_LOW
        );
        creditUsed[_msgSender()] = _creditUsed - (amount * (uint(1 ether)) / (10**decimals));

        SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), vault, amount);
    }

    function releaseToken(
        uint internalId,
        uint16 _chainId
    ) external {
        require(
            hasRole(AUDITOR_ROLE, _msgSender()),
            Errors.P_ONLY_AUDITOR
        );

        bytes32 freeKey = keccak256(abi.encode(internalId, _chainId));

        ICCAL.FreezeTokenInfo memory freezeInfo = freezeMap[freeKey];

        require(freezeInfo.amount > 0 && !freezeInfo.useCredit, Errors.VL_RELEASE_TOKEN_CONDITION_NOT_MATCH);

        delete freezeMap[freeKey];

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(freezeInfo.token), freezeInfo.operator, freezeInfo.amount);
    }
}
