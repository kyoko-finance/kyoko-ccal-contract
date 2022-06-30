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

import "./interface.sol";

contract StorageLayer {
    mapping(address => ICCAL.InterestInfo[]) public pendingWithdraw;

    mapping(bytes32 => ICCAL.FreezeTokenInfo) public freezeMap;

    // uint is wei
    mapping(address => uint) public creditUsed;

    // uint8 public currencyDecimals;

    // address public currency;
}
