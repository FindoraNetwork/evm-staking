// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract Power is Ownable,AccessControlEnumerable {
    bytes32 public constant PlAT_FORM_ROLE = keccak256("PlAT_FORM");

    address public system; // System contract address
    address public stakingAddress; // Staking contract address

    uint256 public powerTotal;

    struct Validator {
        bytes public_key;
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
    function getPower(address validator) public view returns (uint256) {
        require(hasRole(PlAT_FORM_ROLE, msg.sender),"deny of service");
        return validators[validator].power;
    }

    // Increase power for validator
    function addPower(address validator, uint256 power) public {
        require(hasRole(PlAT_FORM_ROLE, msg.sender),"deny of service");
        validators[validator].power += power;
        powerTotal += power;
    }

    // Decrease power for validator
    function descPower(address validator, uint256 power) public {
        require(hasRole(PlAT_FORM_ROLE, msg.sender),"deny of service");
        validators[validator].power -= power;
        powerTotal -= power;
    }
}
