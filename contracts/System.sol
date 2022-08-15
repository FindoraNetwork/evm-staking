// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/Interfaces.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./common/Power.sol";

contract System is Ownable {
    // Staking contract address
    address public stakingAddress;

    // Power contract address
    address public powerAddress;

    // Reword contract address
    address public rewardAddress;

    // Validator power
    mapping(address => uint256) powers;

    // Validator public key
    mapping(address => bytes) pubKeys;

    constructor(
        address powerAddress_,
        address stakingAddress_,
        address rewardAddress_
    ) {
        powerAddress = powerAddress_;
        rewardAddress = rewardAddress_;
        stakingAddress = stakingAddress_;
    }

    function SetConfig(
        address powerAddress_,
        address stakingAddress_,
        address rewardAddress_
    ) public onlyOwner {
        powerAddress = powerAddress_;
        rewardAddress = rewardAddress_;
        stakingAddress = stakingAddress_;
    }

    // Increase power for validator
    function addPower(address validator, uint256 power) public onlyOwner {
        Power powerContract = Power(powerAddress);
        powerContract.addPower(validator, power);
    }

    // Decrease power for validator
    function descPower(address validator, uint256 power) public onlyOwner {
        Power powerContract = Power(powerAddress);
        powerContract.descPower(validator, power);
    }

    // trigger events at end-block
    function blockTrigger() public onlyOwner {
        // Return unDelegate assets
        Staking staking = Staking(stakingAddress);
        staking.trigger();
    }
}
