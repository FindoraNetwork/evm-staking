// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Reward {
    /*
     * Claim assets
     * validator， proposer
     * amount， last_vote_percent
     */
    function claim(address validator, uint256 amount) external {}

    // Punish validator
    function punish() public {}
}
