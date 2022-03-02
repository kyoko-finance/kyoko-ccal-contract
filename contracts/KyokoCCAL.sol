// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { ValidateLogic } from "./libs/ValidateLogic.sol";
import "./BaseContract.sol";
import "./interface.sol";

contract KyokoCCAL is BaseContract {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize(ICreditSystem _creditSystem, bool _isMainChain, address _vault, uint _fee) public override initializer {
        BaseContract.initialize(_creditSystem, _isMainChain, _vault, _fee);
    }

    event DepositAsset(
        address indexed game,
        address indexed depositor,
        uint indexed internalId,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle,
        uint[] toolIds,
        uint index
    );
    function depositAsset(
        address game,
        uint[] memory toolIds,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) public whenNotPaused {
        ValidateLogic.checkDepositPara(game, toolIds, amountPerDay, totalAmount, minPay, cycle);

        uint internalId = getInternalId();

        for (uint i = 0; i < toolIds.length; i++) {
            IERC721Upgradeable(game).safeTransferFrom(_msgSender(), address(this), toolIds[i]);
        }

        nftMap[internalId] = DepositTool({
            depositTime: block.timestamp,
            amountPerDay: amountPerDay,
            status: AssetStatus.INITIAL,
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

        EnumerableSetUpgradeable.UintSet storage holderIds = nftHolderMap[_msgSender()];
        holderIds.add(internalId);

        emit DepositAsset(game, _msgSender(), internalId, amountPerDay, totalAmount, minPay, cycle, toolIds, holderIds.length());
    }

    event EditDepositAsset(
        address indexed game,
        address indexed editor,
        uint indexed internalId,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    );
    function editDepositAsset(
        address game,
        uint internalId,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) public whenNotPaused {
        ValidateLogic.checkEditPara(
            game,
            _msgSender(),
            internalId,
            amountPerDay,
            totalAmount,
            minPay,
            cycle,
            nftMap
        );

        DepositTool memory asset = nftMap[internalId];

        nftMap[internalId] = DepositTool({
            depositTime: asset.depositTime,
            amountPerDay: amountPerDay,
            status: AssetStatus.INITIAL,
            totalAmount: totalAmount,
            internalId: internalId,
            toolIds: asset.toolIds,
            holder: _msgSender(),
            borrower: address(0),
            game: asset.game,
            minPay: minPay,
            borrowTime: 0,
            cycle: cycle
        });

        emit EditDepositAsset(game, _msgSender(), internalId, amountPerDay, totalAmount, minPay, cycle);
    }

    event WithdrawAsset(address indexed game, address indexed depositor, uint indexed internalId);
    function withdrawAsset(
        address game,
        uint internalId
    ) public whenNotPaused {
        DepositTool storage asset = nftMap[internalId];

        bool isRepay     = getIsRepay(asset.status);
        bool isBorrowed  = getIsBorrowed(asset.status);
        bool isWithdraw  = getIsWithdraw(asset.status);
        bool isLiquidate = getIsLiquidate(asset.status);
        bool isExpired   = block.timestamp >= asset.depositTime + asset.cycle;

        require(
            !isWithdraw && !isLiquidate &&
            _msgSender() == asset.holder,
            "bad parameters"
        );

        // if tool isn't borrow or borrowed and repay, depositor can withdraw
        if (!isBorrowed || (isBorrowed && isRepay)) {
            EnumerableSetUpgradeable.UintSet storage idList = nftHolderMap[_msgSender()];

            asset.status = AssetStatus.WITHDRAW;
            idList.remove(internalId);

            for (uint idx; idx < asset.toolIds.length; idx++) {
                IERC721Upgradeable(game).safeTransferFrom(address(this), _msgSender(), asset.toolIds[idx]);
            }

            emit WithdrawAsset(game, _msgSender(), internalId);
        } else {
            require(isExpired, "not expired");
            liquidate(game, internalId);
        }
    }

    event Liquidation(address indexed game, address indexed depositor, address indexed borrower, uint internalId, uint amount);
    // trigger liquidate when borrowing relationship is expired and borrower isn't repay tool
    function liquidate(address game, uint internalId) internal {

        DepositTool storage asset = nftMap[internalId];
        EnumerableSetUpgradeable.UintSet storage holderIds = nftHolderMap[asset.holder];
        EnumerableSetUpgradeable.UintSet storage borrowIds = nftBorrowMap[asset.borrower];

        asset.status = AssetStatus.LIQUIDATE;
        holderIds.remove(internalId);
        borrowIds.remove(internalId);

        if (isMainChain) {
            pendingWithdrawInterest[asset.holder].push(
                InterestInfo({
                    amount: asset.totalAmount,
                    internalId: internalId,
                    game: game
                })
            );

            delete freezeMap[getFreezeKey(game, internalId)];
        }

        // bot should catch this event adn sync main chain data via clearInfoAfterLiquidateViaBot
        emit Liquidation(game, asset.holder, asset.borrower, internalId, asset.totalAmount);
    }

    event RepayAsset(
        address indexed game,
        address indexed depositor,
        address indexed borrower,
        uint internalId,
        uint interest
    );
    function repayAsset(address game, address holder, uint internalId) public {

        ValidateLogic.checkRepayAssetPara(game, _msgSender(), internalId, nftMap);

        DepositTool storage asset = nftMap[internalId];

        for (uint idx; idx < asset.toolIds.length; idx++) {
            IERC721Upgradeable(game).safeTransferFrom(_msgSender(), address(this), asset.toolIds[idx]);
        }

        _afterRepay(game, holder, _msgSender(), internalId);
    }

    function _afterRepay(
        address game,
        address holder,
        address borrower,
        uint internalId
    ) internal {
        DepositTool storage asset = nftMap[internalId];

        uint interest = calcCost(
            asset.amountPerDay,
            block.timestamp - asset.borrowTime,
            asset.minPay,
            asset.totalAmount
        );

        asset.borrowTime = 0;
        asset.borrower = address(0);
        asset.status = AssetStatus.INITIAL;

        EnumerableSetUpgradeable.UintSet storage idList = nftBorrowMap[borrower];

        idList.remove(internalId);

        if (isMainChain) {
            pendingWithdrawInterest[holder].push(
                InterestInfo({
                    internalId: internalId,
                    amount: interest,
                    game: game
                })
            );

            bytes memory key = getFreezeKey(game, internalId);
            FreezeTokenInfo storage freezeToken = freezeMap[key];

            if (freezeToken.useCredit) {
                decreaseCreditUsed(_msgSender(), freezeToken.amount - interest);
                delete freezeMap[key];
            } else {
                freezeToken.game = address(0);
                freezeToken.interest = interest;
            }
        }

        emit RepayAsset(game, holder, borrower, internalId, interest);
    }

    function withdrawToolInterest(
        address game,
        uint internalId
    ) public whenNotPaused {
        require(isMainChain, "only allow operate on main chain");

        (bool canWithdraw, uint index) = ValidateLogic.checkWithdrawToolInterest(game, _msgSender(), internalId, pendingWithdrawInterest);

        require(canWithdraw, "can't withdraw interest");

        InterestInfo[] storage infos = pendingWithdrawInterest[_msgSender()];

        InterestInfo memory info = infos[index];

        infos[index] = infos[infos.length - 1];
        infos.pop();

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(allowCurrency), _msgSender(), (100 - fee) * info.amount / 100);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(allowCurrency), vault, fee * info.amount / 100);
    }

    event BorrowAsset(address indexed game, address indexed borrower, uint indexed internalId);
    // freeze token for asset which deposit on main chain
    event FreezeToken(
        address indexed game,
        address indexed holder,
        address indexed borrower,
        uint internalId,
        bool useCredit
    );
    function freezeTokenForMainChainAsset(
        address game,
        address holder,
        uint internalId,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle,
        bool useCredit
    ) public whenNotPaused {
        require(isMainChain, "only freeze on main chain");

        address caller = msg.sender;
        bytes memory key = getFreezeKey(game, internalId);

        bool canBorrow = ValidateLogic.checkFreezePara(
            game,
            internalId,
            amountPerDay,
            totalAmount,
            minPay,
            cycle,
            freezeMap,
            nftMap
        );

        require(canBorrow, "can not borrow this asset now");

        DepositTool memory asset = nftMap[internalId];

        if (!useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(allowCurrency), caller, address(this), asset.totalAmount);
        } else {
            if (
                checkUserIsInCreditSystem(caller) &&
                (getUserCreditTotalAmount(caller) - getUsed(caller) >= asset.totalAmount)
            ) {
                increaseCreditUsed(caller, asset.totalAmount);
            } else {
                revert("can't use credit borrow");
            }
        }

        freezeMap[key] = FreezeTokenInfo({
            amount: asset.totalAmount,
            internalId: internalId,
            useCredit: useCredit,
            operator: caller,
            game: game,
            interest: 0
        });

        _sendAssetToBorrower(game, caller, internalId);

        emit FreezeToken(game, holder, caller, internalId, useCredit);
        emit BorrowAsset(game, caller, internalId);
    }

    // freeze token for asset which deposit on other chain
    // caution⚠️: before freeze token, check asset expire time first 
    function freezeTokenForOtherChainAsset(
        address game,
        address holder,
        uint internalId,
        uint amount,
        bool useCredit
    ) public whenNotPaused {
        require(isMainChain, "only freeze on main chain");
        bool canBorrow = ValidateLogic.checkFreezeForOtherChainPara(game, internalId, freezeMap);
        require(canBorrow, "can't borrow asset now");

        address caller = msg.sender;
        bytes memory key = getFreezeKey(game, internalId);

        if (!useCredit) {
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(allowCurrency), caller, address(this), amount);
        } else {
            if (checkUserIsInCreditSystem(caller)) {
                uint totalCreditAmount = getUserCreditTotalAmount(caller);
                require(totalCreditAmount - getUsed(caller) >= amount, "not enough");
                increaseCreditUsed(caller, amount);
            } else {
                revert("can not use credit borrow");
            }
        }

        freezeMap[key] = FreezeTokenInfo({
            internalId: internalId,
            useCredit: useCredit,
            operator: caller,
            amount: amount,
            game: game,
            interest: 0
        });

        emit FreezeToken(game, holder, caller, internalId, useCredit);
    }

    // only trigger by bot after liquidation on other chain
    // all parameters are passed via event
    function clearInfoAfterLiquidateViaBot(
        address game,
        address holder,
        uint internalId,
        uint amount
    ) public whenNotPaused onlyBot {

        pendingWithdrawInterest[holder].push(
            InterestInfo({
                internalId: internalId,
                amount: amount,
                game: game
            })
        );
        delete freezeMap[getFreezeKey(game, internalId)];
    }

    // call by bot after repay on other chain
    function syncInterestAfterRepayViaBot(
        address game,
        address holder,
        uint internalId,
        uint interest
    ) public onlyBot {
        pendingWithdrawInterest[holder].push(
            InterestInfo({
                internalId: internalId,
                amount: interest,
                game: game
            })
        );

        bytes memory key = getFreezeKey(game, internalId);
        FreezeTokenInfo storage freezeToken = freezeMap[key];
        if (freezeToken.useCredit) {
            decreaseCreditUsed(_msgSender(), freezeToken.amount - interest);
            delete freezeMap[key];
        } else {
            freezeToken.game = address(0);
            freezeToken.interest = interest;
        }
    }

    function _sendAssetToBorrower(
        address game,
        address borrower,
        uint internalId
    ) internal {
        DepositTool storage asset = nftMap[internalId];
        EnumerableSetUpgradeable.UintSet storage borrowIds = nftBorrowMap[asset.borrower];

        asset.borrower = borrower;
        asset.status = AssetStatus.BORROW;
        asset.borrowTime = block.timestamp;

        borrowIds.add(internalId);

        for (uint idx; idx < asset.toolIds.length; idx++) {
            IERC721Upgradeable(game).safeTransferFrom(address(this), borrower, asset.toolIds[idx]);
        }
    }

    function borrowAssetViaBot(
        address game,
        address borrower,
        uint internalId,
        uint amount,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) public whenNotPaused onlyBot {
        bool canBorrow = ValidateLogic.checkBorrowAssetViaBot(
            game,
            internalId,
            amount,
            amountPerDay,
            totalAmount,
            minPay,
            cycle,
            nftMap
        );

        require(canBorrow, "can not borrow this asset right now");

        _sendAssetToBorrower(game, borrower, internalId);

        emit BorrowAsset(game, borrower, internalId);
    }

    function withdrawFreezeTokenViaBot(
        address game,
        address user,
        uint internalId
    ) public whenNotPaused onlyBot {
        bytes memory key = getFreezeKey(game, internalId);

        FreezeTokenInfo memory freezeToken = freezeMap[key];

        delete freezeMap[key];

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(allowCurrency), user, freezeToken.amount - freezeToken.interest);
    }

    function repayCredit(uint amount) public whenNotPaused {
        require(amount > 0, "bad amount parameters");
        require(creditUsed[_msgSender()] > 0 , "no credit debt to repay");
        SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(allowCurrency), _msgSender(), vault, amount);
        decreaseCreditUsed(_msgSender(), amount);
    }

    event WithDraw(address recipient, uint256 amount);
    function withdraw(uint256 amount) public onlyManager {
        uint balance = IERC20Upgradeable(allowCurrency).balanceOf(address(this));
        require(amount <= balance, "no enough balance");
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(allowCurrency), payable(vault), amount);

        emit WithDraw(vault, amount);
    }

    function getRepayAmount(uint internalId) public view returns(uint) {
        DepositTool memory asset = nftMap[internalId];

        // bad case
        if (asset.internalId != internalId) {
            return 0;
        }

        if (asset.status == AssetStatus.LIQUIDATE) {
            return 0;
        }

        return calcCost(
            asset.amountPerDay,
            block.timestamp - asset.borrowTime,
            asset.minPay,
            asset.totalAmount
        );
    }

    function getCreditUsedAmount(address user) public view returns(uint) {
        return creditUsed[user];
    }

    function getFreezeKey(address game,uint internalId) public pure returns(bytes memory) {
        return bytes.concat(
            abi.encodePacked(game),
            abi.encodePacked(internalId)
        );
    }

    // Check if the borrower has freezed tokens on the main chain
    function checkTokenIsFreezed(
        address game,
        address user,
        uint internalId
    ) public view returns(bool, uint) {
        bytes memory key = getFreezeKey(game, internalId);
        FreezeTokenInfo memory freeze = freezeMap[key];

        if (freeze.game == game && freeze.operator == user) {
            return (true, freeze.amount);
        }
        return (false, 0);
    }

    // if asset expire time is too short, borrow this asset isn't allowed
    function checkAssetExpireTime(uint internalId) public view returns(uint) {
        DepositTool memory asset = nftMap[internalId];

        if (asset.internalId != internalId) {
            return 0;
        }

        if (block.timestamp - asset.depositTime >= asset.cycle) {
            return 0;
        }
        return asset.depositTime + asset.cycle - block.timestamp;
    }

    // server call this function to check if whether user can withdraw specify freezed token
    // if return true, call withdrawFreezeTokenViaBot method
    // otherwise, reject withdraw request
    function checkCanWithdrawFreezeToken(
        address game,
        address user,
        uint internalId
    ) public view returns(bool) {
        bytes memory key = getFreezeKey(game, internalId);

        FreezeTokenInfo memory freezeToken = freezeMap[key];

        return (
            freezeToken.game == address(0) &&
            freezeToken.operator == user &&
            !freezeToken.useCredit
        );
    }

    function releaseTokenEmergency(
        address game,
        address user,
        uint internalId
    ) public onlyManager {
        bytes memory key = getFreezeKey(game, internalId);

        require(freezeMap[key].amount > 0, "no token needs release");

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(allowCurrency), user, freezeMap[key].amount);

        delete freezeMap[key];
    }

    function getUserDepositList(address user) public view returns(uint[] memory) {
        return nftHolderMap[user].values();
    }

    function getUserBorrowList(address user) public view returns(uint[] memory) {
        return nftBorrowMap[user].values();
    }
}
