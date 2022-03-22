// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import { ProjectConfig } from "./ProjectConfig.sol";

import { StorageLayer } from "./StorageLayer.sol";

import "./interface.sol";

contract BaseContract
    is AccessControlEnumerableUpgradeable,
    ERC721HolderUpgradeable,
    StorageLayer,
    ProjectConfig
{
    using SafeMathUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    CountersUpgradeable.Counter private _internalId;

    function initialize(ICreditSystem _creditSystem, bool _isMainChain, address _vault, uint _fee) public virtual initializer {
        fee = _fee;
        vault = _vault;
        isMainChain  = _isMainChain;
        creditSystem = _creditSystem;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    modifier whenNotPaused() {
        require(!_paused);
        _;
    }

    modifier whenPaused() {
        require(_paused);
        _;
    }

    modifier onlyManager() {
        require(
            hasRole(MANAGER_ROLE, _msgSender()),
            "only manager"
        );
        _;
    }

    modifier onlyBot() {
        require(
            hasRole(ROBOT_ROLE, _msgSender()),
            "only robot"
        );
        _;
    }

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

    function paused() public view returns(bool) {
        return _paused;
    }

    function setCreditSystem(ICreditSystem _creditSystem) public onlyManager {
        creditSystem = _creditSystem;
    }

    function setFee(uint _fee) public onlyManager {
        require(fee < 100, "too large");
        fee = _fee;
    }

    function setVault(address _vault) public onlyManager {
        vault = _vault;
    }

    function addNormalTokens(address _token) public onlyManager {
        normal_tokens.add(_token);
    }

    function removeNormalTokens(address _token) public onlyManager {
        normal_tokens.remove(_token);
    }

    function setStableTokens(address _stableToken) public onlyManager {
        stable_tokens.add(_stableToken);
    }

    function removeStableTokens(address _stableToken) public onlyManager {
        stable_tokens.remove(_stableToken);
    }

    function setMaxDiscount(uint _discount) public onlyManager {
        max_discount = _discount;
    }

    function setDiscountPercent(uint _discountPercent) public onlyManager {
        discount_percent = _discountPercent;
    }

    function pause() public onlyManager {
        _paused = true;
    }

    function unpause() public  onlyManager whenPaused {
        _paused = false;
    }

    function calcCost(uint amountPerDay, uint time, uint min, uint max) internal pure returns(uint result) {
        uint cost = time * amountPerDay / 1 days;
        if (cost <= min) {
            result = min;
        } else {
            result = cost > max ? max : cost;
        }
    }

    function getInternalId() internal returns(uint256 num) {
        _internalId.increment();
        num = _internalId.current();
    }

    function getIsBorrowed(AssetStatus status) internal pure returns(bool) {
        return status == AssetStatus.BORROW;
    }

    function getIsWithdraw(AssetStatus status) internal pure returns(bool) {
        return status == AssetStatus.WITHDRAW;
    }

    function getIsLiquidate(AssetStatus status) internal pure returns(bool) {
        return status == AssetStatus.LIQUIDATE;
    }

    function checkUserIsInCreditSystem(address user) internal returns(bool) {
        (, bool inCCALSystem) = ICreditSystem(creditSystem).getState(user);
        return inCCALSystem;
    }

    function getUserCreditTotalAmount(address user) internal returns(uint) {
        return ICreditSystem(creditSystem).getCCALCreditLine(user);
    }

    function increaseCreditUsed(
        address _user,
        uint _amount
    ) internal {
        creditUsed[_user] = creditUsed[_user].add(_amount);
    }

    function decreaseCreditUsed(
        address _user,
        uint _amount
    ) internal {
        creditUsed[_user] = creditUsed[_user].sub(_amount);
    }

    function getUsed(address _user)
        internal
        view
        returns(uint result)
    {
        result = creditUsed[_user];
    }

    function checkToken(address _token) internal view returns(bool) {
        return normal_tokens.contains(_token) || stable_tokens.contains(_token);
    }
}
