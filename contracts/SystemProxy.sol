// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./System.sol";

contract SystemProxy is Ownable, Proxy {
    // address of system
    address public systemAddress;

    /**
     * @dev constructor function, for create system and init systemAddress.
     */
    constructor() {
        System system = new System(address(this));
        systemAddress = address(system);
    }

    /**
     * @dev Set system address, this function can only be called by owner.
     * @param systemAddress_ contract address of system
     */
    function adminSetSystemAddress(address systemAddress_)
    public
    onlyOwner
    {
        systemAddress = systemAddress_;
    }

    /**
     * @dev Get system address.
     * @return contract address of system.
     */
    function _implementation() internal view override returns (address) {
        return systemAddress;
    }
}