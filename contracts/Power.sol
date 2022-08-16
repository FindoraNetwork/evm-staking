// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract Power is AccessControlEnumerable {
    bytes32 public constant ADD_POWER_ROLE = keccak256("ADD_POWER");
    bytes32 public constant DESC_POWER_ROLE = keccak256("DESC_POWER");

    address public system; // System contract address
    address public stakingAddress; // Staking contract address

    uint256 public powerTotal;

    struct Validator {
        uint256 power;
        address staker;
    }
    // (validator address => Validator)
    mapping(address => Validator) public validators;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function adminSetSystemAddress(address system_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        system = system_;
    }

    function adminSetStakingAddress(address stakingAddress_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        stakingAddress = stakingAddress_;
    }

    // get validator power
    function getPower(address validator) public view returns (uint256) {
        return validators[validator].power;
    }

    // Increase power for validator
    function addPower(address validator, uint256 power)
        public
        onlyRole(ADD_POWER_ROLE)
    {
        validators[validator].power += power;
        powerTotal += power;
    }

    // Decrease power for validator
    function descPower(address validator, uint256 power)
        public
        onlyRole(DESC_POWER_ROLE)
    {
        validators[validator].power -= power;
        powerTotal -= power;
    }
}
