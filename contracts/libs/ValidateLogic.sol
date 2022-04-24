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

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import "../interface.sol";

library ValidateLogic {
    function checkDepositPara(
        address game,
        uint[] memory toolIds,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle
    ) public view {
        require(
            IERC721Upgradeable(game).supportsInterface(0x80ac58cd) &&
            (cycle > 0 && cycle <= 365 days) &&
            toolIds.length > 0 &&
            amountPerDay > 0 &&
            totalAmount > 0 &&
            minPay > 0,
            "bad para"
        );
    }

    function checkEditPara(
        address editor,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle,
        uint internalId,
        mapping(uint => DepositAsset) storage assetMap
    ) external view {
        DepositAsset memory asset = assetMap[internalId];
        require(
            (cycle > 0 && cycle <= 365 days) &&
            amountPerDay > 0 &&
            totalAmount > 0 &&
            minPay > 0,
            "bad para"
        );

        require(
            asset.status == AssetStatus.INITIAL &&
            asset.holder == editor,
            "bad para"
        );
    }

    function checkBorrowPara(
        uint internalId,
        uint amountPerDay,
        uint totalAmount,
        uint minPay,
        uint cycle,
        mapping(uint => DepositAsset) storage assetMap
    ) public view returns(bool) {
        DepositAsset memory asset = assetMap[internalId];
        if (
            asset.depositTime + asset.cycle <= block.timestamp ||
            asset.status != AssetStatus.INITIAL ||
            asset.internalId != internalId
        ) {
            return false;
        }
        // prevent depositor change data before borrower freeze token
        if (asset.amountPerDay != amountPerDay || asset.totalAmount != totalAmount || asset.minPay != minPay || asset.cycle != cycle) {
            return false;
        }
        return true;
    }

    function checkWithdrawTokenPara(
        address user,
        uint16 chainId,
        uint internalId,
        mapping(address => InterestInfo[]) storage pendingWithdraw
    ) public view returns(bool, uint) {
        InterestInfo[] memory list = pendingWithdraw[user];
        if (list.length < 1) {
            return (false, 0);
        }
        uint index;
        for (uint i; i < list.length; i++) {
            if (
                list[i].chainId == chainId &&
                list[i].internalId == internalId 
            ) {
                index = i;
                break;
            }
        }
        if (list[index].internalId != internalId) {
            return (false, 0);
        }
        return (true, index);
    }

    function calcCost(uint amountPerDay, uint time, uint min, uint max) external pure returns(uint) {
        uint cost = time * amountPerDay / 1 days;
        if (cost <= min) {
            return min;
        } else {
            return cost > max ? max : cost;
        }
    }
}
