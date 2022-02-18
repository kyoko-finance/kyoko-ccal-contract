// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

// import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

// /** ⚠️this contract is for test. ignore plz */

// contract Game is ERC721Upgradeable, ERC721HolderUpgradeable {

//     event NFTReceived(
//         address indexed operator,
//         address indexed from,
//         uint256 indexed tokenId,
//         bytes data
//     );

//     function initialize(string memory _name, string memory _symbol) public initializer {
//         super.__ERC721_init(_name, _symbol);
//     }

//     function onERC721Received(
//         address operator,
//         address from,
//         uint256 tokenId,
//         bytes memory data
//     ) public override(ERC721HolderUpgradeable) returns (bytes4) {
//         emit NFTReceived(operator, from, tokenId, data);
//         return
//             bytes4(
//                 keccak256("onERC721Received(address,address,uint256,bytes)")
//             );
//     }

//     function mint(address account, uint tokenId) public {
//         super._mint(account, tokenId);
//     }
// }
