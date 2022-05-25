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
        currency         = _currency;
        currencyDecimals = _currencyDecimal;

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
        uint[] memory toolIds,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) external {
        ValidateLogic.checkDepositPara(game, toolIds, amountPerDay, totalAmount, minPay, cycle);

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
            borrowTime: 0,
            game: game,
            cycle: cycle
        });

        emit LogDepositAsset(game, _msgSender(), internalId);
    }

    event LogEditDepositAsset(
        address indexed game,
        address indexed editor,
        uint indexed internalId
    );
    function editDepositAsset(
        uint _internalId,
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

        nftMap[_internalId] = ICCAL.DepositAsset({
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
            borrowTime: 0,
            cycle: cycle
        });

        emit LogEditDepositAsset(nftMap[_internalId].game, _msgSender(), _internalId);
    }

    event LogBorrowAsset(address indexed game, address indexed borrower, uint indexed internalId);
    function _borrow(address _borrower, uint _internalId) internal {
        ICCAL.DepositAsset storage asset = nftMap[_internalId];

        asset.borrower = _borrower;
        asset.status = ICCAL.AssetStatus.BORROW;
        asset.borrowTime = block.timestamp;

        for (uint i; i < asset.toolIds.length; i++) {
            IERC721Upgradeable(asset.game).safeTransferFrom(address(this), _borrower, asset.toolIds[i]);
        }

        emit LogBorrowAsset(asset.game, _borrower, _internalId);
    }

    function borrowAsset(
        uint _internalId,
        uint _amountPerDay,
        uint _totalAmount,
        uint _minPay,
        uint _cycle,
        bool _useCredit
    ) external {
        require(freezeMap[this.getFreezeKey(_internalId, selfChainId)].operator == address(0), "bad req");

        require(ValidateLogic.checkBorrowPara(
            _internalId,
            _amountPerDay,
            _totalAmount,
            _minPay,
            _cycle,
            nftMap
        ), "can not borrow");
        ICCAL.DepositAsset memory asset = nftMap[_internalId];

        if (!_useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(currency), _msgSender(), address(this), asset.totalAmount);
        } else {
            require(this.checkSuitCredit(_msgSender(), asset.totalAmount), "can not use");
            creditUsed[_msgSender()] = creditUsed[_msgSender()].add(
                asset.totalAmount
                    .mul(uint(1 ether))
                    .div(10**currencyDecimals)
                );
        }

        freezeMap[this.getFreezeKey(_internalId, selfChainId)] = ICCAL.FreezeTokenInfo({
            amount: asset.totalAmount,
            useCredit: _useCredit,
            operator: _msgSender()
        });

        _borrow(_msgSender(), _internalId);
    }

    function checkSuitCredit(
        address user,
        uint amount
    ) external returns(bool) {
        bool canBorrow;
        (, bool inCCALSystem) = ICreditSystem(creditSystem).getState(user);
        uint amountInWei = amount.mul(uint(1 ether)).div(10**currencyDecimals);
        if (inCCALSystem) {
            uint creditLine = ICreditSystem(creditSystem).getCCALCreditLine(user);
            if (amountInWei.add(creditUsed[user]) > creditLine) {
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
        uint _cycle,
        bool _useCredit
    ) external payable {
        require(freezeMap[this.getFreezeKey(_internalId, _dstChainId)].operator == address(0), "can't borrow now");

        freezeMap[this.getFreezeKey(_internalId, _dstChainId)] = ICCAL.FreezeTokenInfo({
            amount: _totalAmount,
            useCredit: _useCredit,
            operator: _msgSender()
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
                    _cycle
                )
            ),
            false,
            abi.encodePacked(VERSION, GAS_FOR_DEST_LZ_RECEIVE)
        );

        require(msg.value >= messageFee, "msg.value too low");

        if (!_useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(currency), _msgSender(), address(this), _totalAmount);
        } else {
            require(this.checkSuitCredit(_msgSender(), _totalAmount), "can't use credit");
            creditUsed[_msgSender()] = creditUsed[_msgSender()].add(
                _totalAmount
                    .mul(uint(1 ether))
                    .div(10**currencyDecimals)
                );
        }

        layerZeroEndpoint.send{value: msg.value}(
            _dstChainId,                          // destination chainId
            remotes[_dstChainId],                 // destination address of nft contract
            abi.encode(
                ICCAL.Operation.BORROW,
                abi.encode(
                    _msgSender(),
                    _internalId,
                    _amountPerDay,
                    _totalAmount,
                    _minPay,
                    _cycle
                )
            ),                       // abi.encoded()'ed bytes
            payable(_msgSender()),   // refund address
            address(0x0),            // 'zroPaymentAddress' unused for this
            abi.encodePacked(VERSION, GAS_FOR_DEST_LZ_RECEIVE)                       // txParameters 
        );
    }

    function repayAsset(uint _internalId) external {
        ICCAL.DepositAsset memory asset = nftMap[_internalId];

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

        updateDataAfterRepay(asset.holder, _internalId, selfChainId, interest);
    }

    event LogWithdrawAsset(address indexed game, address indexed depositor, uint indexed internalId);
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

            emit LogWithdrawAsset(asset.game, _msgSender(), internalId);
        } else {
            require(block.timestamp > asset.depositTime + asset.cycle, "not expired");
            liquidate(internalId);
        }
    }

    event LogWithdrawToken(address indexed user, uint amount);
    function withdrawToken(uint16 _chainId, uint _internalId) external {
        (bool canWithdraw, uint index) = ValidateLogic.checkWithdrawTokenPara(
            _msgSender(),
            _chainId,
            _internalId,
            pendingWithdraw
        );
        require(canWithdraw, "can not withdraw");
        ICCAL.InterestInfo[] storage list = pendingWithdraw[_msgSender()];

        ICCAL.InterestInfo memory item = list[index];

        list[index] = list[list.length - 1];
        list.pop();

        uint toVault;
        uint toUser = item.amount;
        if (item.isRent) {
            toVault = item.amount.mul(fee).div(BASE_FEE);
            toUser  = item.amount.mul(BASE_FEE - fee).div(BASE_FEE);
        }
        if (toVault > 0) {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(currency), vault, toVault);
        }
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(currency), _msgSender(), toUser);

        emit LogWithdrawToken(_msgSender(), item.amount);
    }

    event LogLiquidation(address indexed game, uint internalId);
    function liquidate(uint internalId) internal {

        ICCAL.DepositAsset storage asset = nftMap[internalId];

        asset.status = ICCAL.AssetStatus.LIQUIDATE;
        delete freezeMap[this.getFreezeKey(internalId, selfChainId)];

        recordWithdraw(asset.holder, true, internalId, selfChainId, asset.totalAmount);
        emit LogLiquidation(asset.game, internalId);
    }

    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload);
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        // boilerplate: only allow this endpiont to be the caller of lzReceive!
        require(msg.sender == address(layerZeroEndpoint));
        // owner must have setRemote() to allow its remote contracts to send to this contract
        require(
            _srcAddress.length == remotes[_srcChainId].length && keccak256(_srcAddress) == keccak256(remotes[_srcChainId]),
            "bad remote addr"
        );

        try this.onLzReceive(_srcChainId, _srcAddress, _nonce, _payload) {
            // do nothing
        } catch {
            // error / exception
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload);
        }
    }

    function onLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) public {
        // only internal transaction
        require(msg.sender == address(this), "only Bridge.");

        // handle incoming message
        _LzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    event UnknownOp(bytes payload);
    function _LzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal {
        // decode
        (ICCAL.Operation op, bytes memory _other) = abi.decode(_payload, (ICCAL.Operation, bytes));
        if (op == ICCAL.Operation.REPAY) {
            handleRepayAsset(_other);
        } else if (op == ICCAL.Operation.LIQUIDATE) {
            handleLiquidate(_other);
        } else {
            emit UnknownOp(_payload);
        }
    }

    function recordWithdraw(
        address user,
        bool _isRent,
        uint internalId,
        uint16 _chainId,
        uint amount
    ) internal {
        pendingWithdraw[user].push(
            ICCAL.InterestInfo({
                internalId: internalId,
                chainId: _chainId,
                isRent: _isRent,
                amount: amount
            })
        );
    }

    // only execute on main-chain
    function handleRepayAsset(bytes memory _payload) internal {
        (
            address _holder,
            uint _internalId,
            uint16 _chainId,
            uint _interest
        ) = abi.decode(
            _payload,
            (address, uint, uint16, uint)
        );

        updateDataAfterRepay(_holder, _internalId, _chainId, _interest);
    }

    function updateDataAfterRepay(
        address assetHolder,
        uint _internalId,
        uint16 _chainId,
        uint _interest
    ) internal {
        ICCAL.FreezeTokenInfo memory info = freezeMap[this.getFreezeKey(_internalId, _chainId)];
        delete freezeMap[this.getFreezeKey(_internalId, _chainId)];

        recordWithdraw(assetHolder, true, _internalId, _chainId, _interest);

        if (info.useCredit) {
            creditUsed[info.operator] = creditUsed[info.operator].sub(
                (info.amount - _interest)
                .mul(uint(1 ether))
                .div(10**currencyDecimals)
            );
        } else if (info.amount > _interest) {
            recordWithdraw(info.operator, false, _internalId, _chainId, info.amount - _interest);
        }
    }

    /**
        @dev when liquidate on other-chain, main-chain will sync the freeze info
     */
    function handleLiquidate(bytes memory _payload) internal {
        (
            address _holder,
            uint16 _chainId,
            uint _internalId
        ) = abi.decode(
            _payload,
            (address, uint16, uint)
        );

        ICCAL.FreezeTokenInfo memory info = freezeMap[this.getFreezeKey(_internalId, _chainId)];

        delete freezeMap[this.getFreezeKey(_internalId, _chainId)];

        recordWithdraw(_holder, true, _internalId, _chainId, info.amount);
    }

    function repayCredit(uint amount) external {
        require(amount > 0, "bad amount");
        require(creditUsed[_msgSender()] > 0, "bad req");
        require(
            amount.mul(uint(1 ether)).div(10**currencyDecimals) <= creditUsed[_msgSender()],
            "bad amount"
        );
        SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(currency), _msgSender(), vault, amount);

        creditUsed[_msgSender()] = creditUsed[_msgSender()].sub(
            amount
            .mul(uint(1 ether))
            .div(10**currencyDecimals)
        );
    }

    function releaseToken(
        uint internalId,
        uint16 _chainId
    ) external onlyAuditor {

        ICCAL.FreezeTokenInfo memory freezeToken = freezeMap[this.getFreezeKey(internalId, _chainId)];

        require(freezeToken.amount > 0 && !freezeToken.useCredit, "bad req");

        delete freezeMap[this.getFreezeKey(internalId, _chainId)];

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(currency), freezeToken.operator, freezeToken.amount);
    }

    function withdrawETH() external onlyOwner returns(bool) {
        (bool success, ) = _msgSender().call{value: address(this).balance}(new bytes(0));
        return success;
    }
}
