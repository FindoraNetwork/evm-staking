// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Power.sol";
import "./Staking.sol";
import "./Reward.sol";
import "./interfaces/ISystem.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract System is Ownable, ISystem {
    address private __self = address(this);

    // address of proxy contract
    address public proxy_contract;

    // Staking contract address
    address public stakingAddress;

    // Reword contract address
    address public rewardAddress;

    address public powerAddress;

    // Validator-info set Maximum length
    uint256 public validatorSetMaximum;

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

    function adminSetStakingAddress(address stakingAddress_) public onlyOwner {
        stakingAddress = stakingAddress_;
    }

    function adminSetRewardAddress(address rewardAddress_) public onlyOwner {
        rewardAddress = rewardAddress_;
    }

    function adminSetPowerAddress(address powerAddress_) public onlyOwner {
        powerAddress = powerAddress_;
    }

    function adminSetValidatorSetMaximum(uint256 validatorSetMaximum_)
        public
        onlyOwner
    {
        validatorSetMaximum = validatorSetMaximum_;
    }

    function getValidatorInfoList()
        external
        view
        override
        returns (ValidatorInfo[] memory)
    {
        Staking sc = Staking(stakingAddress);

        address[] memory addrs = sc.getAllValidators();

        Power pc = Power(powerAddress);

        ValidatorInfo[] memory vs = new ValidatorInfo[](addrs.length);
        ValidatorInfo[] memory vsRes;
        if (addrs.length > validatorSetMaximum) {
            vsRes = new ValidatorInfo[](validatorSetMaximum);
        } else {
            vsRes = new ValidatorInfo[](addrs.length);
        }

        for (uint256 i = 0; i != addrs.length; i++) {
            address validator = addrs[i];
            (bytes memory public_key, , , ) = sc.validators(validator);
            uint256 power = pc.getPower(validator);

            ValidatorInfo memory v = ValidatorInfo(
                public_key,
                validator,
                power
            );

            vs[i] = v;
        }

        ValidatorInfo[] memory vsDesc = descSort(vs);

        for (uint256 i = 0; i != vsDesc.length; i++) {
            if (i >= validatorSetMaximum) {
                break;
            }
            vsRes[i] = vsDesc[i];
        }

        return vsRes;
    }

    function descSort(ValidatorInfo[] memory validators)
        internal
        pure
        returns (ValidatorInfo[] memory)
    {
        for (uint256 i = 0; i < validators.length - 1; i++) {
            for (uint256 j = 0; j < validators.length - 1 - i; j++) {
                if (validators[j].power < validators[j + 1].power) {
                    ValidatorInfo memory temp = validators[j];
                    validators[j] = validators[j + 1];
                    validators[j + 1] = temp;
                }
            }
        }
        return validators;
    }

    function blockTrigger(
        address proposer,
        address[] memory signed,
        uint256 circulationAmount,
        address[] memory byztine,
        ByztineBehavior[] memory behavior
    ) external override {
        Staking staking = Staking(stakingAddress);
        staking.trigger();
        Reward reward = Reward(rewardAddress);
        reward.reward(proposer, signed, circulationAmount);
        reward.punish(byztine, behavior);
    }

    function getClaimOps() external view override returns (ClaimOps[] memory) {
        ClaimOps[] memory claimOps;
        uint256 claimAmount;
        Reward reward = Reward(rewardAddress);
        address[] memory claimAccounts = reward.getClaimAccount();
        for (uint256 i = 0; i < claimAccounts.length; i++) {
            claimAmount = claimAmount = reward.getClaimAmount(claimAccounts[i]);
            claimOps[i] = ClaimOps(claimAccounts[i], claimAmount);
        }
        return claimOps;
    }
}
