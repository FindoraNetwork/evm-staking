// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Power is Ownable {
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

    modifier onlyPlatform() {
        require(
            msg.sender == system || msg.sender == stakingAddress,
            "deny of service"
        );
        _;
    }

    // get validator power
    function getPower(address validator)
        public
        view
        onlyPlatform
        returns (uint256)
    {
        return validators[validator].power;
    }

    // Increase power for validator
    function addPower(address validator, uint256 power) public onlyPlatform {
        validators[validator].power += power;
        powerTotal += power;
    }

    // Decrease power for validator
    function descPower(address validator, uint256 power) public onlyPlatform {
        validators[validator].power -= power;
        powerTotal -= power;
    }
}
