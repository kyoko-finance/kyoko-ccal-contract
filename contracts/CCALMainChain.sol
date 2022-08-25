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
    using SafeMathUpgradeable for uint;

    uint16 public constant BASE_FEE = 10000;

    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    uint public fee;

    address public vault;

    ICreditSystem public creditSystem;

    modifier onlyAuditor() {
        require(
            hasRole(AUDITOR_ROLE, _msgSender()),
            Errors.P_ONLY_AUDITOR
        );
        _;
    }

    function initialize(
        ICreditSystem _creditSystem,
        address _vault,
        uint _fee,
        uint16 _selfChainId,
        address _endPoint,
        address _currency,
        uint8 _currencyDecimal
    ) public initializer {
        fee              = _fee;
        vault            = _vault;
        creditSystem     = _creditSystem;
        // currency         = _currency;
        // currencyDecimals = _currencyDecimal; // currency for creditSystem 

        tokenInfos[_currency].active = true;
        tokenInfos[_currency].decimals = _currencyDecimal;
        tokenInfos[_currency].stable = true;

        BaseContract.initialize(_endPoint, _selfChainId);
    }

    function setCreditSystem(ICreditSystem _creditSystem) external onlyOwner {
        creditSystem = _creditSystem;
    }

    function setFee(uint _fee) external onlyOwner {
        require(fee <= 1000, Errors.SET_FEE_TOO_LARGE);
        fee = _fee;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), Errors.SET_VAULT_ADDRESS_INVALID);
        vault = _vault;
    }

    event LogBorrowAsset(address indexed borrower, uint indexed internalId, uint borrowIndex, bool useCredit, uint time);
    function _borrow(address _borrower, uint _internalId, bool _useCredit) internal {
        ICCAL.DepositAsset storage asset = nftMap[_internalId];

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

        emit LogBorrowAsset(_borrower, _internalId, asset.borrowIndex, _useCredit, asset.borrowTime);
    }

    function borrowAsset(
        uint _internalId,
        uint _amountPerDay,
        uint _totalAmount,
        uint _minPay,
        uint _cycle,
        bool _useCredit
    ) external {
        bytes32 freeKey = this.getFreezeKey(_internalId, selfChainId);
        require(freezeMap[freeKey].operator == address(0), Errors.VL_BORROW_ALREADY_FREEZE);

        require(ValidateLogic.checkBorrowPara(
            _internalId,
            _amountPerDay,
            _totalAmount,
            _minPay,
            _cycle,
            nftMap
        ), Errors.VL_BORROW_PARAM_NOT_MATCH);

        address _token = nftMap[_internalId].token;
        uint amount = nftMap[_internalId].totalAmount;

        if (!_useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), address(this), amount);
        } else {
            require(tokenInfos[_token].stable == true, Errors.VL_TOKEN_NOT_MATCH_CREDIT);
            uint8 decimals = tokenInfos[_token].decimals;
            require(this.checkSuitCredit(_msgSender(), amount, decimals), Errors.VL_CREDIT_NOT_VALID);
            creditUsed[_msgSender()] = creditUsed[_msgSender()].add(
                amount
                    .mul(uint(1 ether))
                    .div(10**decimals)
            );
        }

        freezeMap[freeKey] = ICCAL.FreezeTokenInfo({
            amount: amount,
            useCredit: _useCredit,
            operator: _msgSender(),
            token: _token
        });

        _borrow(_msgSender(), _internalId, _useCredit);
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
            if (amount.mul(uint(1 ether)).div(10**decimals).add(creditUsed[user]) <= creditLine) {
                canBorrow = true;
            }
        }
        return canBorrow;
    }

    function estimateCrossChainBorrowFees(
        uint16 _dstChainId,
        uint _internalId,
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
                    _internalId,
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
        uint _internalId,
        uint _amountPerDay,
        uint _totalAmount,
        uint _minPay,
        address _token,
        uint _cycle,
        bool _useCredit
    ) external payable {
        bytes32 freeKey = this.getFreezeKey(_internalId, _dstChainId);
        require(freezeMap[freeKey].operator == address(0), Errors.VL_BORROW_ALREADY_FREEZE);

        require(checkTokenInList(_token), Errors.VL_TOKEN_NOT_SUPPORT);

        freezeMap[freeKey] = ICCAL.FreezeTokenInfo({
            amount: _totalAmount,
            useCredit: _useCredit,
            operator: _msgSender(),
            token: _token
        });

        uint messageFee = estimateCrossChainBorrowFees(
            _dstChainId,
            _internalId,
            _amountPerDay,
            _totalAmount,
            _minPay,
            _token,
            _cycle,
            _useCredit
        );

        require(msg.value >= messageFee, Errors.LZ_GAS_TOO_LOW);

        if (!_useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), address(this), _totalAmount);
        } else {
            require(tokenInfos[_token].stable == true, Errors.VL_TOKEN_NOT_MATCH_CREDIT);
            uint8 decimals = tokenInfos[_token].decimals;
            require(this.checkSuitCredit(_msgSender(), _totalAmount, decimals), Errors.VL_CREDIT_NOT_VALID);
            creditUsed[_msgSender()] = creditUsed[_msgSender()].add(
                _totalAmount
                    .mul(uint(1 ether))
                    .div(10**decimals)
            );
        }

        layerZeroEndpoint.send{value: msg.value}(
            _dstChainId,                          // destination chainId
            remotes[_dstChainId],                 // destination address of ccal contract
            abi.encode(
                ICCAL.Operation.BORROW,
                abi.encode(
                    _msgSender(),
                    _internalId,
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
    function repayAsset(uint _internalId) external {
        ICCAL.DepositAsset storage asset = nftMap[_internalId];
        require(asset.status == ICCAL.AssetStatus.BORROW && asset.borrower == _msgSender(), Errors.VL_REPAY_CONDITION_NOT_MATCH);

        uint len = asset.toolIds.length;
        for (uint idx = 0; idx < len;) {
            IERC721Upgradeable(asset.game).safeTransferFrom(_msgSender(), address(this), asset.toolIds[idx]);

            unchecked {
                ++idx;
            }
        }

        _afterRepay(_internalId);
    }

    function _afterRepay(uint _internalId) internal {
        ICCAL.DepositAsset storage asset = nftMap[_internalId];

        uint interest = ValidateLogic.calcCost(
            asset.amountPerDay,
            block.timestamp - asset.borrowTime,
            asset.minPay,
            asset.totalAmount
        );

        asset.borrowTime = 0;
        asset.borrower = address(0);
        asset.status = ICCAL.AssetStatus.INITIAL;

        updateDataAfterRepay(asset.holder, _internalId, selfChainId, interest, asset.borrowIndex);

        emit LogRepayAsset(_internalId, interest, asset.borrowIndex, block.timestamp);
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
    function withdrawToken(uint16 _chainId, uint _internalId, uint _borrowIdx) external {
        (bool canWithdraw, uint index) = findTokenPara(_chainId, _internalId, _borrowIdx);
        require(canWithdraw, Errors.VL_WITHDRAW_TOKEN_PARAM_NOT_MATCH);
        ICCAL.InterestInfo[] storage list = pendingWithdraw[_msgSender()];

        ICCAL.InterestInfo memory item = list[index];

        list[index] = list[list.length - 1];
        list.pop();

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(item.token), _msgSender(), item.amount);

        emit LogWithdrawToken(remotes[_chainId], _chainId, _internalId, _borrowIdx, _msgSender(), item.amount);
    }

    function findTokenPara(uint16 _chainId, uint _internalId, uint _borrowIdx) public view returns(bool, uint) {
        (bool canWithdraw, uint index) = ValidateLogic.checkWithdrawTokenPara(
            _msgSender(),
            _chainId,
            _internalId,
            _borrowIdx,
            pendingWithdraw
        );
        return (canWithdraw, index);
    }

    event LogLiquidation(uint internalId, uint time);
    function liquidate(uint internalId) internal {

        ICCAL.DepositAsset storage asset = nftMap[internalId];

        asset.status = ICCAL.AssetStatus.LIQUIDATE;

        bytes32 freeKey = this.getFreezeKey(internalId, selfChainId);

        ICCAL.FreezeTokenInfo memory info = freezeMap[freeKey];
        delete freezeMap[freeKey];

        uint toVault = info.amount * fee / BASE_FEE;
        if (!info.useCredit) {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), vault, toVault);
        }

        recordWithdraw(asset.holder, internalId, selfChainId, info.amount - toVault, info.token, asset.borrowIndex);
        emit LogLiquidation(internalId, block.timestamp);
    }

    // event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload);
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64,
        bytes memory _payload
    ) external override {
        // boilerplate: only allow this endpiont to be the caller of lzReceive!
        require(msg.sender == address(layerZeroEndpoint), Errors.LZ_BAD_SENDER);
        // owner must have setRemote() to allow its remote contracts to send to this contract
        require(
            _srcAddress.length == remotes[_srcChainId].length && keccak256(_srcAddress) == keccak256(remotes[_srcChainId]),
            Errors.LZ_BAD_REMOTE_ADDR
        );

        _LzReceive(_payload);

        // try this.onLzReceive(_srcChainId, _srcAddress, _nonce, _payload) {
            // do nothing
        // } catch {
            // error / exception
            // emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload);
        // }
    }

    // function onLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) public {
        // only internal transaction
        // require(msg.sender == address(this), "only Bridge.");

        // handle incoming message
        // _LzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    // }

    // event UnknownOp(bytes payload);
    function _LzReceive(bytes memory _payload) internal {
    // function _LzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal {
        // decode
        (ICCAL.Operation op, bytes memory _other) = abi.decode(_payload, (ICCAL.Operation, bytes));
        if (op == ICCAL.Operation.REPAY) {
            handleRepayAsset(_other);
        } else if (op == ICCAL.Operation.LIQUIDATE) {
            handleLiquidate(_other);
        } else {
            // emit UnknownOp(_payload);
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
            uint _internalId,
            uint16 _chainId,
            uint _interest,
            uint _borrowIndex
        ) = abi.decode(
            _payload,
            (address, uint, uint16, uint, uint)
        );

        updateDataAfterRepay(_holder, _internalId, _chainId, _interest, _borrowIndex);
    }

    function updateDataAfterRepay(
        address assetHolder,
        uint _internalId,
        uint16 _chainId,
        uint _interest,
        uint _borrowIndex
    ) internal {
        bytes32 freeKey = this.getFreezeKey(_internalId, _chainId);

        ICCAL.FreezeTokenInfo memory info = freezeMap[freeKey];
        delete freezeMap[freeKey];

        uint interest = _interest > info.amount ? info.amount : _interest; // 0.04k

        uint toVault = interest * fee / BASE_FEE;

        recordWithdraw(assetHolder, _internalId, _chainId, interest - toVault, info.token, _borrowIndex);

        if (info.useCredit) {
            creditUsed[info.operator] = creditUsed[info.operator].sub(
                (info.amount - interest)
                    .mul(uint(1 ether))
                    .div(10**tokenInfos[info.token].decimals)
            );
        } else {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), vault, toVault);
            recordWithdraw(info.operator, _internalId, _chainId, info.amount - interest, info.token, _borrowIndex);
        }
    }

    /**
        @dev when liquidate on other-chain, main-chain will sync the freeze info
     */
    function handleLiquidate(bytes memory _payload) internal {
        (
            address _holder,
            uint16 _chainId,
            uint _internalId,
            uint _borrowIndex
        ) = abi.decode(
            _payload,
            (address, uint16, uint, uint)
        );

        bytes32 freeKey = this.getFreezeKey(_internalId, _chainId);

        ICCAL.FreezeTokenInfo memory info = freezeMap[freeKey];

        delete freezeMap[freeKey];

        uint toVault = info.amount * fee / BASE_FEE;
        if (!info.useCredit) {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), vault, toVault);
        }

        recordWithdraw(_holder, _internalId, _chainId, info.amount - toVault, info.token, _borrowIndex);
    }

    function repayCredit(uint amount, address _token) external {
        require(amount > 0, Errors.VL_REPAY_CREDIT_AMOUNT_0);
        require(checkTokenInList(_token), Errors.VL_TOKEN_NOT_SUPPORT);

        uint _creditUsed = creditUsed[_msgSender()];
        require(_creditUsed > 0, Errors.VL_REPAY_CREDIT_NO_NEED);

        uint8 decimals = tokenInfos[_token].decimals;

        require(
            amount.mul(uint(1 ether)).div(10**decimals) <= _creditUsed,
            Errors.VL_REPAY_CREDIT_AMOUNT_TOO_LOW
        );
        SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), vault, amount);

        creditUsed[_msgSender()] = _creditUsed.sub(
            amount
                .mul(uint(1 ether))
                .div(10**decimals)
        );
    }

    function releaseToken(
        uint internalId,
        uint16 _chainId
    ) external onlyAuditor {

        bytes32 freeKey = this.getFreezeKey(internalId, _chainId);

        ICCAL.FreezeTokenInfo memory freezeInfo = freezeMap[freeKey];

        require(freezeInfo.amount > 0 && !freezeInfo.useCredit, "bad req");

        delete freezeMap[freeKey];

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(freezeInfo.token), freezeInfo.operator, freezeInfo.amount);
    }

    function withdrawETH() external onlyOwner returns(bool) {
        (bool success, ) = _msgSender().call{value: address(this).balance}(new bytes(0));
        return success;
    }
}
