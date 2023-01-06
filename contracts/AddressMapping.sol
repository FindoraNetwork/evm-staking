// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract AddressMapping is Initializable, AccessControlEnumerableUpgradeable {
    bytes32 public constant WRITABLE_ROLE = keccak256("WRITABLE_ROLE");

    mapping(address => bytes) public addressMapping;

    function initialize() public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function adminSetStakingAddress(address addr) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setupRole(WRITABLE_ROLE, addr);
    }

    function setMap(address addr, bytes calldata pk)
        public
        onlyRole(WRITABLE_ROLE)
    {
        addressMapping[addr] = pk;
    }
}
