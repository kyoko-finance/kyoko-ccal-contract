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
            "only auditor"
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
        require(fee <= 1000, "too large");
        fee = _fee;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "bad vault");
        vault = _vault;
    }

    event LogDepositAsset(
        address indexed game,
        address indexed depositor,
        uint indexed internalId
    );
    function deposit(
        address game,
        address token,
        uint[] memory toolIds,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) external {
        ValidateLogic.checkDepositPara(game, toolIds, amountPerDay, totalAmount, minPay, cycle);
        require(checkTokenInList(token), "unsupported token");

        uint internalId = getInternalId();

        for (uint i = 0; i < toolIds.length; i++) {
            IERC721Upgradeable(game).safeTransferFrom(_msgSender(), address(this), toolIds[i]);
        }

        nftMap[internalId] = ICCAL.DepositAsset({
            depositTime: block.timestamp,
            amountPerDay: amountPerDay,
            status: ICCAL.AssetStatus.INITIAL,
            totalAmount: totalAmount,
            internalId: internalId,
            holder: _msgSender(),
            borrower: address(0),
            toolIds: toolIds,
            minPay: minPay,
            token: token,
            borrowTime: 0,
            game: game,
            cycle: cycle,
            borrowIndex: 0
        });

        emit LogDepositAsset(game, _msgSender(), internalId);
    }

    event LogEditDepositAsset(uint indexed internalId);
    function editDepositAsset(
        uint _internalId,
        address token,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) external whenNotPaused {
        ValidateLogic.checkEditPara(
            _msgSender(),
            amountPerDay,
            totalAmount,
            minPay,
            cycle,
            _internalId,
            nftMap
        );

        require(checkTokenInList(token), "unsupported token");

        nftMap[_internalId] = ICCAL.DepositAsset({
            borrowIndex: nftMap[_internalId].borrowIndex,
            depositTime: nftMap[_internalId].depositTime,
            toolIds: nftMap[_internalId].toolIds,
            game: nftMap[_internalId].game,
            amountPerDay: amountPerDay,
            status: ICCAL.AssetStatus.INITIAL,
            totalAmount: totalAmount,
            internalId: _internalId,
            holder: _msgSender(),
            borrower: address(0),
            minPay: minPay,
            token: token,
            borrowTime: 0,
            cycle: cycle
        });

        emit LogEditDepositAsset(_internalId);
    }

    event LogBorrowAsset(address indexed borrower, uint indexed internalId);
    function _borrow(address _borrower, uint _internalId) internal {
        ICCAL.DepositAsset storage asset = nftMap[_internalId];

        asset.borrowIndex += 1;
        asset.borrower = _borrower;
        asset.borrowTime = block.timestamp;
        asset.status = ICCAL.AssetStatus.BORROW;

        for (uint i; i < asset.toolIds.length; i++) {
            IERC721Upgradeable(asset.game).safeTransferFrom(address(this), _borrower, asset.toolIds[i]);
        }

        emit LogBorrowAsset(_borrower, _internalId);
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
        require(freezeMap[freeKey].operator == address(0), "bad req");

        require(ValidateLogic.checkBorrowPara(
            _internalId,
            _amountPerDay,
            _totalAmount,
            _minPay,
            _cycle,
            nftMap
        ), "can not borrow");

        address _token = nftMap[_internalId].token;
        uint amount = nftMap[_internalId].totalAmount;

        if (!_useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), address(this), amount);
        } else {
            require(tokenInfos[_token].stable == true, "token not match credit");
            uint8 decimals = tokenInfos[_token].decimals;
            require(this.checkSuitCredit(_msgSender(), amount, decimals), "can not use");
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

        _borrow(_msgSender(), _internalId);
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
            if (amount.mul(uint(1 ether)).div(10**decimals).add(creditUsed[user]) > creditLine) {
                canBorrow = true;
            }
        }
        return canBorrow;
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
        require(freezeMap[freeKey].operator == address(0), "can't borrow now");

        require(checkTokenInList(_token), "unsupported token");

        freezeMap[freeKey] = ICCAL.FreezeTokenInfo({
            amount: _totalAmount,
            useCredit: _useCredit,
            operator: _msgSender(),
            token: _token
        });

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
                    _cycle
                )
            ),
            false,
            abi.encodePacked(VERSION, GAS_FOR_DEST_LZ_RECEIVE)
        );

        require(msg.value >= messageFee, "msg.value too low");

        if (!_useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), address(this), _totalAmount);
        } else {
            require(tokenInfos[_token].stable == true, "token not match credit");
            uint8 decimals = tokenInfos[_token].decimals;
            require(this.checkSuitCredit(_msgSender(), _totalAmount, decimals), "can't use credit");
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
                    _cycle
                )
            ),                       // abi.encoded()'ed bytes
            payable(_msgSender()),   // refund address
            address(0x0),            // 'zroPaymentAddress' unused for this
            abi.encodePacked(VERSION, GAS_FOR_DEST_LZ_RECEIVE)                       // txParameters 
        );
    }

    event LogRepayAsset(uint indexed internalId, uint interest, uint time);
    function repayAsset(uint _internalId) external {
        ICCAL.DepositAsset storage asset = nftMap[_internalId];
        require(asset.status == ICCAL.AssetStatus.BORROW && asset.borrower == _msgSender(), "bad req");

        for (uint idx; idx < asset.toolIds.length; idx++) {
            IERC721Upgradeable(asset.game).safeTransferFrom(_msgSender(), address(this), asset.toolIds[idx]);
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

        emit LogRepayAsset(_internalId, interest, block.timestamp);
    }

    event LogWithdrawAsset(uint indexed internalId);
    function withdrawAsset(uint internalId) external whenNotPaused {
        ICCAL.DepositAsset memory asset = nftMap[internalId];

        require(
            (asset.status != ICCAL.AssetStatus.WITHDRAW) &&
            (asset.status != ICCAL.AssetStatus.LIQUIDATE) &&
            _msgSender() == asset.holder,
            "bad parameters"
        );

        // if tool isn't borrow, depositor can withdraw
        if (asset.status == ICCAL.AssetStatus.INITIAL) {
            nftMap[internalId].status = ICCAL.AssetStatus.WITHDRAW;

            for (uint idx; idx < asset.toolIds.length; idx++) {
                IERC721Upgradeable(asset.game).safeTransferFrom(address(this), _msgSender(), asset.toolIds[idx]);
            }

            emit LogWithdrawAsset(internalId);
        } else {
            require(block.timestamp > asset.depositTime + asset.cycle, "not expired");
            liquidate(internalId);
        }
    }

    event LogWithdrawToken(bytes _address, uint indexed internalId, address indexed user, uint amount);
    function withdrawToken(uint16 _chainId, uint _internalId, uint _borrowIdx) external {
        (bool canWithdraw, uint index) = ValidateLogic.checkWithdrawTokenPara(
            _msgSender(),
            _chainId,
            _internalId,
            _borrowIdx,
            pendingWithdraw
        );
        require(canWithdraw, "can not withdraw");
        ICCAL.InterestInfo[] storage list = pendingWithdraw[_msgSender()];

        ICCAL.InterestInfo memory item = list[index];

        list[index] = list[list.length - 1];
        list.pop();

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(item.token), _msgSender(), item.amount);

        emit LogWithdrawToken(remotes[_chainId], _internalId, _msgSender(), item.amount);
    }

    event LogLiquidation(uint internalId);
    function liquidate(uint internalId) internal {

        ICCAL.DepositAsset storage asset = nftMap[internalId];

        asset.status = ICCAL.AssetStatus.LIQUIDATE;
        delete freezeMap[this.getFreezeKey(internalId, selfChainId)];

        recordWithdraw(asset.holder, true, internalId, selfChainId, asset.totalAmount, asset.token, asset.borrowIndex);
        emit LogLiquidation(internalId);
    }

    // event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload);
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64,
        bytes memory _payload
    ) external override {
        // boilerplate: only allow this endpiont to be the caller of lzReceive!
        require(msg.sender == address(layerZeroEndpoint));
        // owner must have setRemote() to allow its remote contracts to send to this contract
        require(
            _srcAddress.length == remotes[_srcChainId].length && keccak256(_srcAddress) == keccak256(remotes[_srcChainId]),
            "bad remote addr"
        );

        _LzReceive(_payload);
        // onLzReceive(_srcChainId, _srcAddress, _nonce, _payload);

        // try this.onLzReceive(_srcChainId, _srcAddress, _nonce, _payload) {
            // do nothing
        // } catch {
            // error / exception
            // emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload);
        // }
    }

    // function onLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal {
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
        bool _isLent,
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
                isLent: _isLent,
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

        uint toVault = _interest * fee / BASE_FEE;

        recordWithdraw(assetHolder, true, _internalId, _chainId, _interest - toVault, info.token, _borrowIndex);

        if (info.useCredit) {
            creditUsed[info.operator] = creditUsed[info.operator].sub(
                _interest
                    .mul(uint(1 ether))
                    .div(10**tokenInfos[info.token].decimals)
            );
        } else {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), vault, toVault);
            recordWithdraw(info.operator, false, _internalId, _chainId, info.amount - _interest, info.token, _borrowIndex);
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

        recordWithdraw(_holder, true, _internalId, _chainId, info.amount - toVault, info.token, _borrowIndex);
    }

    function repayCredit(uint amount, address _token) external {
        require(amount > 0, "bad amount");
        require(checkTokenInList(_token), "unsupported token");

        uint _creditUsed = creditUsed[_msgSender()];
        require(_creditUsed > 0, "bad req");

        uint8 decimals = tokenInfos[_token].decimals;

        require(
            amount.mul(uint(1 ether)).div(10**decimals) <= _creditUsed,
            "bad amount"
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

    function getToolIds(uint internalId) external view returns(uint[] memory toolIds) {
        toolIds = nftMap[internalId].toolIds;
    }
}
