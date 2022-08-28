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

library Help {
    function getKey(uint id, uint16 chainId) external pure returns(bytes32) {
        return keccak256(abi.encode(id, chainId));
    }
}
