// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// /** ⚠️this contract is for test. ignore plz */

// contract USDT is ERC20 {
//     using SafeERC20 for IERC20;

//     address internal owner;

//     constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
//         _mint(msg.sender, 1000);
//         owner = msg.sender;
//     }

//     modifier onlyOwner() {
//         require(msg.sender == owner);
//         _;
//     }

//     function mint(address account, uint amount) public onlyOwner  {
//         _mint(account, amount * (10 ** decimals()));
//     }
// }
