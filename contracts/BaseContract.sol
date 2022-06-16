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

import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { ProjectConfig } from "./ProjectConfig.sol";
import "./LayerZero/ILayerZeroUserApplicationConfig.sol";
import "./LayerZero/ILayerZeroReceiver.sol";
import "./LayerZero/ILayerZeroEndpoint.sol";

contract BaseContract is
    ProjectConfig,
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC721HolderUpgradeable,
    AccessControlEnumerableUpgradeable,
    ILayerZeroReceiver,
    ILayerZeroUserApplicationConfig
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    CountersUpgradeable.Counter private _internalId;

    uint16 public selfChainId;

    event NFTReceived(
        address indexed operator,
        address indexed from,
        uint256 indexed tokenId,
        bytes data
    );

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public override(ERC721HolderUpgradeable) returns (bytes4) {
        emit NFTReceived(operator, from, tokenId, data);
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function initialize(
        address _endpoint,
        uint16 _selfChainId
    ) public virtual initializer {
        selfChainId = _selfChainId;
        layerZeroEndpoint = ILayerZeroEndpoint(_endpoint);

        __Ownable_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function getInternalId() internal returns(uint) {
        _internalId.increment();
        return _internalId.current();
    }

    function lzReceive(
        uint16,
        bytes memory,
        uint64, /*_nonce*/
        bytes memory/*_payload*/
    ) external virtual override {}

    function setRemote(uint16 _chainId, bytes calldata _remoteAdr) external onlyOwner {
        remotes[_chainId] = _remoteAdr;
    }

    function setConfig(
        uint16, /*_version*/
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external override {
        layerZeroEndpoint.setConfig(layerZeroEndpoint.getSendVersion(address(this)), _chainId, _configType, _config);
    }

    function getConfig(
        uint16, /*_dstChainId*/
        uint16 _chainId,
        address,
        uint _configType
    ) external view returns (bytes memory) {
        return layerZeroEndpoint.getConfig(layerZeroEndpoint.getSendVersion(address(this)), _chainId, address(this), _configType);
    }

    function setSendVersion(uint16 version) external override {
        layerZeroEndpoint.setSendVersion(version);
    }

    function setReceiveVersion(uint16 version) external override {
        layerZeroEndpoint.setReceiveVersion(version);
    }

    function getSendVersion() external view returns (uint16) {
        return layerZeroEndpoint.getSendVersion(address(this));
    }

    function getReceiveVersion() external view returns (uint16) {
        return layerZeroEndpoint.getReceiveVersion(address(this));
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override {
        layerZeroEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    function getFreezeKey(
        uint _id,
        uint16 _chainId
    ) external pure returns(bytes32) {
        return keccak256(abi.encodePacked(_id, _chainId));
    }

    function addTokens(address _token, uint8 _decimals, bool stable) external onlyOwner {
        tokenInfos[_token].active = true;
        tokenInfos[_token].decimals = _decimals;
        tokenInfos[_token].stable = stable;
    }

    function removeTokens(address _token) external onlyOwner {
        delete tokenInfos[_token];
    }

    function checkTokenInList(address _token) internal view returns(bool) {
        return tokenInfos[_token].active;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    fallback() external payable {}

    receive() external payable {}
}
