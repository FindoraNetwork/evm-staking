// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Power.sol";
import "./interfaces/Interfaces.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract System is Ownable {
    // address of proxy contract
    address public proxy_contract;

    // Staking contract address
    address public stakingAddress;

    // Reword contract address
    address public rewardAddress;

    // Validator power
    //    mapping(address => uint256) powers;

    // Validator public key
    //    mapping(address => bytes) pubKeys;

    /**
     * @dev constructor function, for init proxy_contract.
     * @param _proxy_contract address of proxy contract.
     */
    constructor(address _proxy_contract) {
        proxy_contract = _proxy_contract;
    }

    modifier onlyProxy() {
        require(
            msg.sender == proxy_contract,
            "Only proxy can call this function"
        );
        _;
    }

    function SetConfig(address stakingAddress_, address rewardAddress_)
        public
        onlyOwner
    {
        rewardAddress = rewardAddress_;
        stakingAddress = stakingAddress_;
    }

    // trigger events at end-block
    function blockTrigger() public onlyProxy {
        // Return unDelegate assets
        Staking staking = Staking(stakingAddress);
        staking.trigger();
    }
}
