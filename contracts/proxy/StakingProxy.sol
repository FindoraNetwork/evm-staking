// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @dev StakingProxy proxy contract that can be upgrade
 */
contract StakingProxy is TransparentUpgradeableProxy {
    address public proxyAdmin;

    constructor(
        address _logic,
        address _admin,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, _admin, _data) {
        proxyAdmin = _admin;
    }
}
