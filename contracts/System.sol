// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IBase.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IPower.sol";
import "./interfaces/IReward.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract System is Ownable, IBase {
    address public __self = address(this);

    // address of proxy contract
    address public proxyAddress;

    // Staking contract address
    address payable public stakingAddress;

    // Reword contract address
    address public rewardAddress;

    address public powerAddress;

    /**
     * @dev constructor function, for init proxy_contract.
     * @param _proxy_contract address of proxy contract.
     */
    constructor(address _proxy_contract) {
        proxyAddress = _proxy_contract;
    }

    modifier onlyProxy() {
        require(
            msg.sender == proxyAddress,
            "Only proxy can call this function"
        );
        _;
    }

    modifier onlySystem() {
        require(msg.sender == address(0), "Only system can call this function");
        _;
    }

    function adminSetProxyAddress(address addr) public onlyOwner {
        proxyAddress = addr;
    }

    function adminSetStakingAddress(address payable addr) public onlyOwner {
        stakingAddress = addr;
    }

    function adminSetRewardAddress(address addr) public onlyOwner {
        rewardAddress = addr;
    }

    function adminSetPowerAddress(address addr) public onlyOwner {
        powerAddress = addr;
    }

    function trigger(
        address proposer,
        address[] calldata signed,
        address[] calldata unsigned,
        address[] calldata byztine,
        ByztineBehavior[] calldata behavior
    ) external onlySystem {
        System system = System(__self);

        system._trigger(proposer, signed, unsigned, byztine, behavior);
    }

    function _trigger(
        address proposer,
        address[] calldata signed,
        address[] calldata unsigned,
        address[] calldata byztine,
        ByztineBehavior[] calldata behavior
    ) external onlyProxy {
        if (stakingAddress != address(0)) {
            // Return unDelegate assets
            IStaking staking = IStaking(stakingAddress);
            staking.trigger();
        }

        if (rewardAddress != address(0)) {
            IReward reward = IReward(rewardAddress);
            reward.reward(proposer, signed);
            reward.punish(unsigned, byztine, behavior);
        }
    }

    function getClaimOps() external onlySystem returns (ClaimOps[] memory) {
        System system = System(__self);

        return system._getClaimOps();
    }

    function _getClaimOps() external onlyProxy returns (ClaimOps[] memory) {
        if (rewardAddress != address(0)) {
            IReward reward = IReward(rewardAddress);
            return reward.getClaimOps();
        } else {
            ClaimOps[] memory ops = new ClaimOps[](0);

            return ops;
        }
    }

    function getValidatorsList() public view returns (ValidatorInfo[] memory) {
        System system = System(__self);

        return system._getValidatorsList();
    }

    function _getValidatorsList() public view returns (ValidatorInfo[] memory) {
        if (powerAddress != address(0)) {
            IPower power = IPower(powerAddress);
            return power.getValidatorsList();
        } else {
            ValidatorInfo[] memory ops = new ValidatorInfo[](0);

            return ops;
        }
    }

    function stake(
        address validator,
        bytes calldata public_key,
        string calldata memo,
        uint256 rate
    ) external payable onlySystem {
        System system = System(__self);
        return system._stake(validator, public_key, memo, rate);
    }

    function _stake(
        address validator,
        bytes calldata public_key,
        string calldata memo,
        uint256 rate
    ) external payable onlyProxy {
        if (stakingAddress != address(0)) {
            // Return unDelegate assets
            IStaking staking = IStaking(stakingAddress);
            staking.stake(validator, public_key, memo, rate);
        }
    }

    function adminStake(
        address validator,
        bytes calldata public_key,
        address staker,
        string calldata memo,
        uint256 rate
    ) external payable onlySystem {
        System system = System(__self);
        return
            system._adminStake{value: msg.value}(
                validator,
                public_key,
                staker,
                memo,
                rate
            );
    }

    function _adminStake(
        address validator,
        bytes calldata public_key,
        address staker,
        string calldata memo,
        uint256 rate
    ) external payable {
        if (stakingAddress != address(0)) {
            IStaking staking = IStaking(stakingAddress);
            staking.adminStake{value: msg.value}(
                validator,
                public_key,
                staker,
                memo,
                rate
            );
        }
    }

    function adminDelegate(
        address validator,
        address delegator
    ) external payable onlySystem {
        System system = System(__self);

        return system._adminDelegate{value: msg.value}(validator, delegator);
    }

    function _adminDelegate(
        address validator,
        address delegator
    ) external payable {
        if (stakingAddress != address(0)) {
            IStaking staking = IStaking(stakingAddress);
            staking.adminDelegate{value: msg.value}(validator, delegator);
        }
    }

    function delegate(address validator) external payable onlySystem {
        System system = System(__self);
        return system._delegate(validator);
    }

    function _delegate(address validator) external payable onlyProxy {
        if (stakingAddress != address(0)) {
            // Return unDelegate assets
            IStaking staking = IStaking(stakingAddress);
            staking.delegate(validator);
        }
    }

    function undelegate(address validator, uint256 amount) external onlySystem {
        System system = System(__self);

        system._undelegate(validator, amount);
    }

    function _undelegate(address validator, uint256 amount) external onlyProxy {
        if (stakingAddress != address(0)) {
            // Return unDelegate assets
            IStaking staking = IStaking(stakingAddress);
            staking.undelegate(validator, amount);
        }
    }

    function claim(uint256 amount) external onlySystem {
        System system = System(__self);

        system._claim(amount);
    }

    function _claim(uint256 amount) external onlyProxy {
        if (rewardAddress != address(0)) {
            IReward reward = IReward(rewardAddress);

            reward.claim(amount);
        }
    }
}
