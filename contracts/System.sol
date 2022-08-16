// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Power.sol";
import "./Staking.sol";
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

    function adminSetStakingAddress(
        address stakingAddress_,
        address rewardAddress_
    ) public onlyOwner {
        rewardAddress = rewardAddress_;
        stakingAddress = stakingAddress_;
    }

    function adminSetRewardAddress(
        address stakingAddress_,
        address rewardAddress_
    ) public onlyOwner {
        rewardAddress = rewardAddress_;
        stakingAddress = stakingAddress_;
    }

    function adminSetPowerAddress(
        address stakingAddress_,
        address rewardAddress_
    ) public onlyOwner {
        rewardAddress = rewardAddress_;
        stakingAddress = stakingAddress_;
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

        return vs;
    }

    function blockTrigger(
        address proposer,
        address[] memory signed,
        address[] memory byztine,
        ByztineBehavior[] memory behavior
    ) external override {
        Staking staking = Staking(stakingAddress);
        staking.trigger();
    }

    function getClaimOps() external override returns (ClaimOps[] memory) {}
}
