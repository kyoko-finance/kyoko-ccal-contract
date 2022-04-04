// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { ValidateLogic } from "./libs/ValidateLogic.sol";
import "./BaseContract.sol";

contract KyokoCCAL is BaseContract {
    using SafeMathUpgradeable for uint;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function initialize(
        ICreditSystem _creditSystem,
        bool _isMainChain,
        address _vault,
        uint _fee,
        uint _chainId
    ) public override initializer {
        BaseContract.initialize(_creditSystem, _isMainChain, _vault, _fee, _chainId);
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
        address token,
        uint[] memory toolIds,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) external whenNotPaused {
        ValidateLogic.checkDepositPara(game, toolIds, amountPerDay, totalAmount, minPay, cycle);
        require(checkTokenInList(token), "bad token");

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
            token: token,
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
        address token,
        uint internalId,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) external whenNotPaused {
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
        require(checkTokenInList(token), "bad token");

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
            token: token,
            borrowTime: 0,
            cycle: cycle
        });

        emit EditDepositAsset(game, _msgSender(), internalId, amountPerDay, totalAmount, minPay, cycle);
    }

    event WithdrawAsset(address indexed game, address indexed depositor, uint indexed internalId);
    function withdrawAsset(
        address game,
        uint internalId
    ) external whenNotPaused {
        DepositTool storage asset = nftMap[internalId];

        bool isBorrowed  = getIsBorrowed(asset.status);
        bool isWithdraw  = getIsWithdraw(asset.status);
        bool isLiquidate = getIsLiquidate(asset.status);
        bool isExpired   = block.timestamp > asset.depositTime + asset.cycle;

        require(
            !isWithdraw && !isLiquidate &&
            _msgSender() == asset.holder,
            "bad parameters"
        );

        // if tool isn't borrow, depositor can withdraw
        if (!isBorrowed) {
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

    event Liquidation(address indexed game, address indexed depositor, address indexed borrower, uint internalId, uint amount, address token);
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
                    token: asset.token,
                    game: game
                })
            );

            delete freezeMap[getFreezeKey(game, internalId, chainId)];
        }

        // bot should catch this event adn sync main chain data via clearInfoAfterLiquidateViaBot
        emit Liquidation(game, asset.holder, asset.borrower, internalId, asset.totalAmount, asset.token);
    }

    event RepayAsset(
        address indexed game,
        address indexed depositor,
        address indexed borrower,
        uint internalId,
        uint interest
    );
    function repayAsset(address game, address holder, uint internalId) external {

        ValidateLogic.checkRepayAssetPara(game, _msgSender(), internalId, nftMap);

        DepositTool memory asset = nftMap[internalId];
        require(asset.holder == holder, "bad req");

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
                    token: asset.token,
                    amount: interest,
                    game: game
                })
            );

            FreezeTokenInfo memory freezeInfo = freezeMap[getFreezeKey(game, internalId, chainId)];

            if (freezeInfo.useCredit) {
                decreaseCreditUsed(freezeInfo.operator, freezeInfo.token, freezeInfo.amount - interest);
            } else {
                if (freezeInfo.amount > interest) {
                    pendingWithdrawFreezeToken[borrower].push(
                        FreezeTokenInfo({
                            amount: freezeInfo.amount - interest,
                            internalId: freezeInfo.internalId,
                            operator: freezeInfo.operator,
                            token: freezeInfo.token,
                            game: freezeInfo.game,
                            useCredit: false,
                            interest: 0
                        })
                    );
                }
            }
            delete freezeMap[getFreezeKey(game, internalId, chainId)];
        }

        emit RepayAsset(game, holder, borrower, internalId, interest);
    }

    event WithdrawToolInterest(
        address indexed game,
        uint indexed internalId,
        uint interestInWei
    );
    function withdrawToolInterest(
        address game,
        uint internalId
    ) external whenNotPaused {
        require(isMainChain, "only main chain");

        (bool canWithdraw, uint index) = ValidateLogic.checkWithdrawToolInterest(game, _msgSender(), internalId, pendingWithdrawInterest);

        require(canWithdraw, "can't withdraw");

        InterestInfo[] storage infos = pendingWithdrawInterest[_msgSender()];

        InterestInfo memory info = infos[index];

        infos[index] = infos[infos.length - 1];
        infos.pop();

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), _msgSender(), (BASE_FEE - fee) * info.amount / BASE_FEE);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), vault, fee * info.amount / BASE_FEE);

        uint amountInWei = (info.amount).mul(uint(1 ether)).div(tokenInfo[info.token].decimals);
        emit WithdrawToolInterest(game, internalId, amountInWei);
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
        bool useCredit,
        address token
    ) external whenNotPaused {
        require(isMainChain, "only main chain");

        if (useCredit) {
            require(stable_tokens.contains(token), "bad token");
        } else {
            require(checkTokenInList(token), "bad token");
        }

        address caller = _msgSender();
        bytes memory key = getFreezeKey(game, internalId, chainId);

        bool canBorrow = ValidateLogic.checkFreezePara(
            game,
            internalId,
            amountPerDay,
            totalAmount,
            minPay,
            cycle,
            chainId,
            freezeMap,
            nftMap
        );

        require(canBorrow, "can't borrow now");

        DepositTool memory asset = nftMap[internalId];

        require(asset.token == token, "bad token");
        if (!useCredit) {
            uint realPayAmount = asset.totalAmount;
            if (discount_percent != 0) {
                uint discount = realPayAmount * discount_percent / 100;
                if (discount > max_discount) {
                    discount = max_discount;
                }
                realPayAmount -= discount;
            }
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(token), caller, address(this), realPayAmount);
        } else {
            // credit borrow no discount rewards
            require(checkUserCanUseCredit(caller, token, asset.totalAmount), "can't use credit");
            increaseCreditUsed(caller, token, asset.totalAmount);
        }

        freezeMap[key] = FreezeTokenInfo({
            amount: asset.totalAmount,
            internalId: internalId,
            useCredit: useCredit,
            operator: caller,
            token: token,
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
        bool useCredit,
        address token,
        uint _chainId
    ) external whenNotPaused {
        require(isMainChain, "only main chain");

        if (useCredit) {
            require(stable_tokens.contains(token), "bad token");
        } else {
            require(checkTokenInList(token), "bad token");
        }

        bool canBorrow = ValidateLogic.checkFreezeForOtherChainPara(game, internalId, _chainId, freezeMap);
        require(canBorrow, "can't borrow now");

        address caller = _msgSender();

        if (!useCredit) {
            uint realPayAmount = amount;
            if (discount_percent != 0) {
                uint discount = realPayAmount * discount_percent / 100;
                if (discount > max_discount) {
                    discount = max_discount;
                }
                realPayAmount -= discount;
            }
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(token), caller, address(this), realPayAmount);
        } else {
            require(checkUserCanUseCredit(caller, token, amount), "can't use credit");
            increaseCreditUsed(caller, token, amount);
        }

        freezeMap[getFreezeKey(game, internalId, _chainId)] = FreezeTokenInfo({
            internalId: internalId,
            useCredit: useCredit,
            operator: caller,
            amount: amount,
            token: token,
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
        uint amount,
        uint _chainId
    ) external whenNotPaused onlyBot {
        
        FreezeTokenInfo memory info = freezeMap[getFreezeKey(game, internalId, _chainId)];

        pendingWithdrawInterest[holder].push(
            InterestInfo({
                internalId: internalId,
                token: info.token,
                amount: amount,
                game: game
            })
        );
        delete freezeMap[getFreezeKey(game, internalId, _chainId)];
    }

    // call by bot after repay on other chain
    function syncInterestAfterRepayViaBot(
        address game,
        address holder,
        uint internalId,
        uint interest,
        uint _chainId
    ) external onlyBot {
        FreezeTokenInfo memory freezeInfo = freezeMap[getFreezeKey(game, internalId, _chainId)];

        pendingWithdrawInterest[holder].push(
            InterestInfo({
                internalId: internalId,
                token: freezeInfo.token,
                amount: interest,
                game: game
            })
        );

        if (freezeInfo.useCredit) {
            decreaseCreditUsed(freezeInfo.operator, freezeInfo.token, freezeInfo.amount - interest);
        } else {
            if (freezeInfo.amount > interest) {
                pendingWithdrawFreezeToken[freezeInfo.operator].push(
                    FreezeTokenInfo({
                        amount: freezeInfo.amount - interest,
                        internalId: freezeInfo.internalId,
                        operator: freezeInfo.operator,
                        token: freezeInfo.token,
                        game: freezeInfo.game,
                        useCredit: false,
                        interest: 0
                    })
                );
            }
        }
        delete freezeMap[getFreezeKey(game, internalId, _chainId)];
    }

    function _sendAssetToBorrower(
        address game,
        address borrower,
        uint internalId
    ) internal {
        DepositTool storage asset = nftMap[internalId];
        EnumerableSetUpgradeable.UintSet storage borrowIds = nftBorrowMap[borrower];

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
        uint cycle,
        address token
    ) external whenNotPaused onlyBot {
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

        require(nftMap[internalId].token == token, "bad token");
        require(canBorrow, "can't borrow now");

        _sendAssetToBorrower(game, borrower, internalId);

        emit BorrowAsset(game, borrower, internalId);
    }

    function withdrawFreezeTokenViaBot(
        address user,
        uint internalId
    ) external whenNotPaused onlyBot {
        require(isMainChain, "only main chain");
        (bool canWithdraw, uint idx) = ValidateLogic.checkWithdrawFreezeTokenPara(
            user,
            internalId,
            pendingWithdrawFreezeToken
        );
        require(canWithdraw, "bad req");

        FreezeTokenInfo[] storage list = pendingWithdrawFreezeToken[user];
        FreezeTokenInfo memory info = list[idx];

        list[idx] = list[list.length - 1];
        list.pop();

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(info.token), user, info.amount);
    }

    function repayCredit(uint amount, address _token) external {
        require(amount > 0, "bad amount");
        require(creditUsed[_msgSender()] > 0, "bad req");
        require(stable_tokens.contains(_token), "bad token");
        uint amountInWei = amount.mul(uint(1 ether)).div(10**tokenInfo[_token].decimals);
        require(amountInWei <= creditUsed[_msgSender()], "bad amount");
        SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), vault, amount);
        decreaseCreditUsed(_msgSender(), _token, amount);
    }

    function getRepayAmount(uint internalId) external view returns(uint) {
        DepositTool memory asset = nftMap[internalId];

        // bad case
        if (asset.internalId != internalId) {
            return 0;
        }

        if (asset.status == AssetStatus.LIQUIDATE) {
            return 0;
        }

        if (asset.status == AssetStatus.INITIAL) {
            return 0;
        }

        return calcCost(
            asset.amountPerDay,
            block.timestamp - asset.borrowTime,
            asset.minPay,
            asset.totalAmount
        );
    }

    function getCreditUsedAmount(address user) external view returns(uint) {
        return creditUsed[user];
    }

    function getFreezeKey(address _game, uint _internalId, uint _chainId) public pure returns(bytes memory) {
        return bytes.concat(
            abi.encodePacked(_game),
            abi.encodePacked(_internalId),
            abi.encodePacked(_chainId)
        );
    }

    // Check if the borrower has freezed tokens on the main chain
    function checkTokenIsFreezed(
        address game,
        address user,
        uint internalId,
        uint _chainId
    ) external view returns(bool, uint, address) {
        bytes memory key = getFreezeKey(game, internalId, _chainId);
        FreezeTokenInfo memory freeze = freezeMap[key];

        if (freeze.game == game && freeze.operator == user) {
            return (true, freeze.amount, freeze.token);
        }
        return (false, 0, address(0));
    }

    // if asset expire time is too short, borrow this asset isn't allowed
    function checkAssetExpireTime(uint internalId) external view returns(uint) {
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
        address user,
        uint internalId
    ) external view returns(bool) {
        (bool canWithdraw,) = ValidateLogic.checkWithdrawFreezeTokenPara(
            user,
            internalId,
            pendingWithdrawFreezeToken
        );
        return canWithdraw;
    }

    function releaseTokenEmergency(
        address game,
        uint internalId,
        uint _chainId
    ) external onlyAuditor {
        bytes memory key = getFreezeKey(game, internalId, _chainId);

        FreezeTokenInfo memory freezeToken = freezeMap[key];

        require(freezeToken.amount > 0, "bad req");

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(freezeToken.token), freezeToken.operator, freezeToken.amount);

        delete freezeMap[key];
    }

    function getTokens() external view returns(address[] memory, address[] memory) {
        return (stable_tokens.values(), normal_tokens.values());
    }
}
