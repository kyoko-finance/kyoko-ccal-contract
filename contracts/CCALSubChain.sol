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

import { ValidateLogic } from "./libs/ValidateLogic.sol";

import "./BaseContract.sol";

import "./interface.sol";

contract CCALSubChain is BaseContract {
    mapping(uint => ICCAL.DepositAsset) public nftMap;

    uint16 public mainChainId;

    function initialize(
        address _endpoint,
        uint16 _selfChainId,
        uint16 _mainChainId
    ) public initializer {
        mainChainId = _mainChainId;

        BaseContract.initialize(_endpoint, _selfChainId);
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
        uint internalId,
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
            internalId,
            nftMap
        );

        nftMap[internalId] = ICCAL.DepositAsset({
            depositTime: nftMap[internalId].depositTime,
            toolIds: nftMap[internalId].toolIds,
            game: nftMap[internalId].game,
            amountPerDay: amountPerDay,
            status: ICCAL.AssetStatus.INITIAL,
            totalAmount: totalAmount,
            internalId: internalId,
            holder: _msgSender(),
            borrower: address(0),
            minPay: minPay,
            borrowTime: 0,
            cycle: cycle
        });

        emit LogEditDepositAsset(nftMap[internalId].game, _msgSender(), internalId);
    }

    function repayAsset(uint internalId) external payable {
        ICCAL.DepositAsset storage asset = nftMap[internalId];

        require(asset.status == ICCAL.AssetStatus.BORROW && asset.borrower == _msgSender(), "bad req");

        for (uint idx; idx < asset.toolIds.length; idx++) {
            IERC721Upgradeable(asset.game).safeTransferFrom(_msgSender(), address(this), asset.toolIds[idx]);
        }

        uint interest = ValidateLogic.calcCost(
            asset.amountPerDay,
            block.timestamp - asset.borrowTime,
            asset.minPay,
            asset.totalAmount
        );

        asset.borrowTime = 0;
        asset.borrower = address(0);
        asset.status = ICCAL.AssetStatus.INITIAL;

        bytes memory payload = abi.encode(
            ICCAL.Operation.REPAY,
            abi.encode(
                asset.holder,
                internalId,
                selfChainId,
                interest
            )
        );

        // encode adapterParams to specify more gas for the destination
        bytes memory adapterParams = abi.encodePacked(VERSION, GAS_FOR_DEST_LZ_RECEIVE);

        // get the fees we need to pay to LayerZero + Relayer to cover message delivery
        // you will be refunded for extra gas paid
        (uint messageFee, ) = layerZeroEndpoint.estimateFees(mainChainId, address(this), payload, false, adapterParams);

        require(msg.value >= messageFee, "msg.value isn't enough");

        layerZeroEndpoint.send{value: msg.value}(
            mainChainId,                     //  destination chainId
            remotes[mainChainId],            //  destination address of nft contract
            payload,                     //  abi.encoded()'ed bytes
            payable(_msgSender()),                    //  refund address
            address(0x0),                      //  'zroPaymentAddress' unused for this
            adapterParams                      //  txParameters 
        );
    }

    event LogBorrowAsset(address indexed game, address indexed borrower, uint indexed internalId);
    function _borrow(address _borrower, uint internalId) internal {
        ICCAL.DepositAsset storage asset = nftMap[internalId];

        asset.borrower = _borrower;
        asset.status = ICCAL.AssetStatus.BORROW;
        asset.borrowTime = block.timestamp;

        for (uint i; i < asset.toolIds.length; i++) {
            IERC721Upgradeable(asset.game).safeTransferFrom(address(this), _borrower, asset.toolIds[i]);
        }

        emit LogBorrowAsset(asset.game, _borrower, internalId);
    }

    event LogWithdrawAsset(address indexed game, address indexed depositor, uint indexed internalId);
    function withdrawAsset(uint internalId) external payable whenNotPaused {
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

            if (msg.value > 0) {
                (bool success, ) = _msgSender().call{value: msg.value, gas: 30_000}(new bytes(0));
                require(success, "failed");
            }
            emit LogWithdrawAsset(asset.game, _msgSender(), internalId);
        } else {
            require(block.timestamp > asset.depositTime + asset.cycle, "not expired");
            liquidate(internalId);
        }
    }

    event LogLiquidation(address indexed game, uint internalId);
    function liquidate(uint internalId) internal {

        ICCAL.DepositAsset storage asset = nftMap[internalId];

        asset.status = ICCAL.AssetStatus.LIQUIDATE;

        bytes memory payload = abi.encode(
            ICCAL.Operation.LIQUIDATE,
            abi.encode(
                asset.holder,
                selfChainId,
                internalId
            )
        );

        // encode adapterParams to specify more gas for the destination
        bytes memory adapterParams = abi.encodePacked(VERSION, GAS_FOR_DEST_LZ_RECEIVE);

        // get the fees we need to pay to LayerZero + Relayer to cover message delivery
        // you will be refunded for extra gas paid
        (uint messageFee, ) = layerZeroEndpoint.estimateFees(mainChainId, address(this), payload, false, adapterParams);

        require(msg.value >= messageFee, "msg.value isn't enough");

        layerZeroEndpoint.send{value: msg.value}(
            mainChainId,                     //  destination chainId
            remotes[mainChainId],            //  destination address of nft contract
            payload,                          //  abi.encoded()'ed bytes
            payable(_msgSender()),                    //  refund address
            address(0x0),                      //  'zroPaymentAddress' unused for this
            adapterParams                      //  txParameters 
        );

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
            "bad remote call"
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
        require(msg.sender == address(this), "caller must be Bridge");

        // handle incoming message
        _LzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    event UnknownOp(bytes payload);
    function _LzReceive(uint16, bytes memory, uint64, bytes memory _payload) internal {
        // decode
        (ICCAL.Operation op, bytes memory _other) = abi.decode(_payload, (ICCAL.Operation, bytes));
        if (op == ICCAL.Operation.BORROW) {
            handleBorrowAsset(_other);
        } else {
            emit UnknownOp(_payload);
        }
    }

    event BorrowFail(address indexed game, address indexed user, uint indexed id);
    function handleBorrowAsset(bytes memory _payload) internal {
        (address user, uint id, uint _dp, uint _total, uint _min, uint _c) = abi.decode(_payload, (address, uint, uint, uint, uint, uint));
        ICCAL.DepositAsset memory asset = nftMap[id];
        bool canBorrow;
        // prevent depositor change data before borrower freeze token
        if (
            asset.depositTime + asset.cycle > block.timestamp &&
            asset.status == ICCAL.AssetStatus.INITIAL &&
            asset.totalAmount == _total &&
            asset.amountPerDay == _dp &&
            asset.internalId == id &&
            asset.minPay == _min &&
            asset.cycle == _c
        ) {
            canBorrow = true;
        }
        if (!canBorrow) {
            emit BorrowFail(asset.game, user, id);
        } else {
            _borrow(user, id);
        }
    }
}
