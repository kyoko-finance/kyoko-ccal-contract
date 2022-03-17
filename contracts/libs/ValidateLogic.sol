// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import "../interface.sol";

library ValidateLogic {
    function checkIsERC721Asset(address asset) internal view returns(bool result) {
        result = IERC721Upgradeable(asset).supportsInterface(0x80ac58cd);
    }

    function getFreezeKey(
        address game,
        uint internalId
    ) public pure returns(bytes memory) {
        return bytes.concat(
            abi.encodePacked(game),
            abi.encodePacked(internalId)
        );
    }

    function checkDepositPara(
        address game,
        uint[] memory toolIds,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) external view {
        require(
            checkIsERC721Asset(game) &&
            (cycle > 0 && cycle < 365 days) &&
            toolIds.length > 0 &&
            amountPerDay > 0 &&
            totalAmount > 0 &&
            minPay > 0,
            "bad parameters"
        );
    }

    function checkEditPara(
        address game,
        address editor,
        uint internalId,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle,
        mapping(uint => DepositTool) storage nftMap
    ) external view {
        require(
            (cycle > 0 && cycle < 365 days) &&
            amountPerDay > 0 &&
            totalAmount > 0 &&
            minPay > 0,
            "bad parameters"
        );

        DepositTool memory asset = nftMap[internalId];

        require(
            asset.status == AssetStatus.INITIAL &&
            asset.holder == editor &&
            asset.game == game,
            "bad parameters"
        );
    }

    function checkWithdrawToolInterest(
        address game,
        address depositor,
        uint internalId,
        mapping(address => InterestInfo[]) storage pendingWithdrawInterest
    ) external view returns(bool, uint) {
        InterestInfo[] memory infos = pendingWithdrawInterest[depositor];
        uint index;
        for (uint i; i < infos.length; i++) {
            if (infos[i].internalId == internalId && infos[i].game == game) {
                index = i;
                break;
            }
        }
        return (infos[index].amount > 0 , index);
    }

    function checkRepayAssetPara(
        address game,
        address borrower,
        uint internalId,
        mapping(uint => DepositTool) storage nftMap
    ) external view {
        DepositTool memory asset = nftMap[internalId];

        require(asset.status == AssetStatus.BORROW, "bad asset status");

        require(
            asset.borrower == borrower &&
            asset.game == game,
            "bad parameters"
        );
    }

    function checkFreezePara(
        address game,
        uint internalId,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle,
        mapping(bytes => FreezeTokenInfo) storage freezeMap,
        mapping(uint => DepositTool) storage nftMap
    ) external view returns(bool) {
        FreezeTokenInfo memory freezeInfo = freezeMap[getFreezeKey(game, internalId)];
        DepositTool memory asset = nftMap[internalId];

        if (asset.status != AssetStatus.INITIAL) {
            return false;
        }
        if (freezeInfo.operator != address(0)) {
            return false;
        }
        if (asset.depositTime + asset.cycle <= block.timestamp) {
            return false;
        }
        if (asset.internalId != internalId) {
            return false;
        }
        // prevent depositor change data before borrower freeze token
        if (asset.amountPerDay != amountPerDay || asset.totalAmount != totalAmount || asset.minPay != minPay || asset.cycle != cycle) {
            return false;
        }
        return true;
    }

    function checkBorrowAssetViaBot(
        address game,
        uint internalId,
        uint amount,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle,
        mapping(uint => DepositTool) storage nftMap
    ) external view returns(bool) {
        DepositTool memory asset = nftMap[internalId];

        if (asset.status != AssetStatus.INITIAL) {
            return false;
        }

        if (amount < asset.totalAmount) {
            return false;
        }
        if (asset.internalId != internalId) {
            return false;
        }
        // prevent depositor change data before borrower freeze token
        if (
            asset.amountPerDay != amountPerDay ||
            asset.totalAmount != totalAmount ||
            asset.minPay != minPay ||
            asset.cycle != cycle ||
            asset.game != game
        ) {
            return false;
        }
        return true;
    }

    function checkFreezeForOtherChainPara(
        address game,
        uint internalId,
        mapping(bytes => FreezeTokenInfo) storage freezeMap
    ) external view returns(bool) {
        FreezeTokenInfo memory freezeInfo = freezeMap[getFreezeKey(game, internalId)];

        if (freezeInfo.operator != address(0)) {
            return false;
        }
        return true;
    }
}
