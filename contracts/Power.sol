// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract Power is Ownable, AccessControlEnumerable {
    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM");
    bytes32 public constant STAKING_ROLE = keccak256("STAKING");

    address public system; // System contract address
    address public stakingAddress; // Staking contract address

    uint256 public powerTotal;

    struct Validator {
        uint256 power;
        address staker;
    }
    // (validator address => Validator)
    mapping(address => Validator) public validators;

    function SetConfig(address system_, address stakingAddress_)
        public
        onlyOwner
    {
        system = system_;
        stakingAddress = stakingAddress_;
    }

    // get validator power
    function getPower(address validator)
        public
        view
        onlyRole(SYSTEM_ROLE)
        onlyRole(STAKING_ROLE)
        returns (uint256)
    {
        return validators[validator].power;
    }

    // Increase power for validator
    function addPower(address validator, uint256 power)
        public
        onlyRole(SYSTEM_ROLE)
        onlyRole(STAKING_ROLE)
    {
        validators[validator].power += power;
        powerTotal += power;
    }

    // Decrease power for validator
    function descPower(address validator, uint256 power)
        public
        onlyRole(SYSTEM_ROLE)
        onlyRole(STAKING_ROLE)
    {
        validators[validator].power -= power;
        powerTotal -= power;
    }
}
