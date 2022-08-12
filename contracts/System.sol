// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/ISystem.sol";
import "./interfaces/Interfaces.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract System is Ownable {
    // Staking contract address
    address public stakingAddress;

    // Reword contract address
    address public rewardAddress;

    // Validator power
    mapping(address => uint256) powers;

    // Validator public key
    mapping(address => bytes) pubkeys;

    // Increase power for validator
    function addPower(address validator, uint256 power) public {}

    // Decrease power for validator
    function descPower(address validator, uint256 power) public {}

    // trigger events at end-block
    function blockTrigger() public {
        // Trigger return assets event
        IStaking staking = IStaking(stakingAddress);
        staking.trigger();
    }
}
