// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Staking.sol";
import "./interfaces/ISystem.sol";
import "./interfaces/IByztine.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract Reward is AccessControlEnumerable, IByztine {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Staking contract address
    address public stakingAddress;
    // Power contract address
    address public powerAddress;

    uint256[2] private duplicateVotePunishRate;
    uint256[2] private lightClientAttackPunishRate;
    uint256[2] private offLinePunishRate;
    uint256[2] private unknownPunishRate;

    // (reward address => reward amount)
    mapping(address => uint256) public rewords;

    mapping(address => uint256) public claimingOps;

    EnumerableSet.AddressSet private claimingSet;

    // (height => reward rate records)
    mapping(uint256 => uint256[2]) public returnRateRecords;

    event Punish(
        address punishAddress,
        ByztineBehavior behavior,
        uint256 amount
    );
    event Rewards(address rewardAddress, uint256 amount);
    event Claim(address claimAddress, uint256 amount);

    constructor(
        uint256[2] memory duplicateVotePunishRate_,
        uint256[2] memory lightClientAttackPunishRate_,
        uint256[2] memory offLinePunishRate_,
        uint256[2] memory unknownPunishRate_,
        address stakingAddress_,
        address powerAddress_
    ) {
        duplicateVotePunishRate = duplicateVotePunishRate_;
        lightClientAttackPunishRate = lightClientAttackPunishRate_;
        offLinePunishRate = offLinePunishRate_;
        unknownPunishRate = unknownPunishRate_;
        stakingAddress = stakingAddress_;
        powerAddress = powerAddress_;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function adminSetDuplicateVotePunishRate(
        uint256[2] calldata duplicateVotePunishRate_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        duplicateVotePunishRate = duplicateVotePunishRate_;
    }

    function adminSetLightClientAttackPunishRate(
        uint256[2] calldata lightClientAttackPunishRate_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        lightClientAttackPunishRate = lightClientAttackPunishRate_;
    }

    function adminSetOffLinePunishRate(uint256[2] calldata offLinePunishRate_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        offLinePunishRate = offLinePunishRate_;
    }

    function adminSetUnknownPunishRate(uint256[2] calldata unknownPunishRate_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        unknownPunishRate = unknownPunishRate_;
    }

    /*
     * Claim assets
     * validator， proposer
     * amount， last_vote_percent
     */
    // 将claim的账户存入集合，待系统调用system合约，拿到当前claim的地址和金额，然后通过coinbase发钱
    function claim(address validator, uint256 amount) external {
        require(rewords[validator] >= amount, "insufficient amount");
        claimingSet.add(validator);
        claimingOps[validator] += amount;
        rewords[validator] -= amount;
    }

    // 处理claim后的更新,清除validator正在claim的数据
    function afterClaim(address[] memory validators) public {
        for (uint256 i = 0; i < validators.length; i++) {
            claimingSet.remove(validators[i]);
        }
    }

    // 获取claim 账户
    function getClaimAccount() public view returns (address[] memory) {
        return claimingSet.values();
    }

    // 获取claim 金额
    function getClaimAmount(address account) public view returns (uint256) {
        return claimingOps[account];
    }

    // Distribute rewards
    function reward(
        address validator, // proposer
        address[] memory signed,
        uint256 circulationAmount
    ) public {
        //        uint256 totalPower;
        //        uint256 signedPower;
        uint256[2] memory returnRateProposer;
        returnRateProposer = lastVotePercent(signed);

        Staking sc = Staking(stakingAddress);
        uint256 totalDelegationAmount = sc.delegateTotal();

        // APY
        uint256[2] memory returnRate;
        returnRate = getBlockReturnRate(
            totalDelegationAmount,
            circulationAmount
        );
        returnRateRecords[block.number] = returnRate;

        // Total rewards
        // (am / total_amount) * (global_amount * ((return_rate[0] / return_rate[1]) / ((365 * 24 * 3600) / block_itv)))
        address staker = validator;
        uint256 am;
        uint256 total_amount;
        uint256 delegateAmount;
        uint256 totalRewards;
        uint256 blockInterval = sc.blockInterval();
        uint256 global_amount = sc.delegateTotal();
        total_amount += sc.getDelegateAmount(staker, staker);
        address[] memory delegators = sc.getDelegators(staker);
        for (uint256 i = 0; i < delegators.length; i++) {
            delegateAmount = sc.getDelegateAmount(staker, delegators[i]);
            am += delegateAmount;
            total_amount += delegateAmount;
        }

        // 给proposer所有的delegator发放奖励
        {
            totalRewards =
                (am / total_amount) *
                (global_amount *
                    ((returnRate[0] / returnRate[1]) /
                        ((365 * 24 * 3600) / blockInterval)));

            // 佣金比例
            uint256 commissionRate = sc.getStakerRate(staker);
            // 佣金，佣金给到这个validator的self-delegator的delegation之中
            uint256 commission = totalRewards * commissionRate;
            // 实际分配给delegator的奖励， 奖励需要按佣金比例扣除佣金,最后剩下的才是奖励
            uint256 realReward = totalRewards - commission;
            // 给proposer所有的delegator发放奖励
            rewardDelegator(staker, realReward);
        }

        // 给proposer发放奖
        uint256 proposerRewards = (am / total_amount) *
            (global_amount *
                ((returnRateProposer[0] / returnRateProposer[1]) /
                    ((365 * 24 * 3600) / blockInterval)));
        sc.addDelegateAmountAndPower(staker, staker, proposerRewards);
        emit Rewards(staker, proposerRewards);
    }

    // Punish validator and delegators
    function punish(address[] memory byztine, ByztineBehavior[] memory behavior)
        public
    {
        Staking sc = Staking(stakingAddress);
        uint256[2] memory punishRate;
        uint256 stakerDelegateAmount;
        uint256 power;
        uint256 stakerPunishAmount;
        for (uint256 i = 0; i < byztine.length; i++) {
            address validator = byztine[i];

            // Check whether the byztine is a stacker
            if (!sc.isStaker(validator)) {
                continue;
            }
            punishRate = getPunishInfo(behavior[i]);

            // Punish staker
            stakerDelegateAmount = sc.getDelegateAmount(validator, validator);
            power =
                ((stakerDelegateAmount * punishRate[0]) / punishRate[1]) /
                (10**12);
            stakerPunishAmount = power * (10**12);
            sc.descDelegateAmountAndPower(
                validator,
                validator,
                stakerPunishAmount
            );
            //            Power powerContract = Power(powerAddress);
            //            powerContract.descPower(validator, power);

            emit Punish(validator, behavior[i], stakerPunishAmount);

            // Punish delegators
            address[] memory delegators = sc.getDelegators(validator);
            uint256 delegateAmount;
            uint256 punishAmount;
            for (uint256 j = 0; j < delegators.length; j++) {
                delegateAmount = sc.getDelegateAmount(delegators[j], validator);
                power =
                    ((delegateAmount * punishRate[0]) / punishRate[1]) /
                    (10**12);
                punishAmount = power * (10**12);
                sc.descDelegateAmountAndPower(
                    validator,
                    delegators[j],
                    punishAmount
                );
                //                powerContract.descPower(validator, power);

                emit Punish(delegators[j], behavior[i], punishAmount);
            }
        }

        // 先检查一遍 staker和delegator的金额和power是否充足，然后再做减操作，后面需要再检查
        // 本金-惩罚金额,本金不足扣奖励,后面再检查
    }

    // Get last vote percent
    function lastVotePercent(address[] memory signed)
        public
        view
        returns (uint256[2] memory)
    {
        Staking sc = Staking(stakingAddress);
        Power powerContract = Power(powerAddress);
        uint256 totalPower = powerContract.powerTotal();
        uint256 signedPower;
        for (uint256 i = 0; i < signed.length; i++) {
            if (sc.isStaker(signed[i])) {
                signedPower += powerContract.getPower(signed[i]);
            }
        }
        uint256[2] memory votePercent = [signedPower, totalPower];
        return votePercent;
    }

    // Get block rewards-rate,计算APY,传入 全局质押比
    function getBlockReturnRate(
        uint256 delegationPercent0,
        uint256 delegationPercent1
    ) public pure returns (uint256[2] memory) {
        uint256 a0 = delegationPercent0 * 536;
        uint256 a1 = delegationPercent1 * 10000;
        if (a0 * 100 > a1 * 268) {
            a0 = 268;
            a1 = 100;
        } else if (a0 * 1000 < a1 * 54) {
            a0 = 54;
            a1 = 1000;
        }
        uint256[2] memory rewardsRate = [a0, a1];
        return rewardsRate;
    }

    function getPunishInfo(ByztineBehavior byztineBehavior)
        internal
        view
        returns (uint256[2] memory)
    {
        uint256[2] memory punishRete;
        if (byztineBehavior == ByztineBehavior.DuplicateVote) {
            punishRete = duplicateVotePunishRate;
        } else if (byztineBehavior == ByztineBehavior.LightClientAttack) {
            punishRete = lightClientAttackPunishRate;
        } else if (byztineBehavior == ByztineBehavior.Unknown) {
            punishRete = unknownPunishRate;
        }

        return punishRete;
    }

    // 给proposer所有的delegator发放奖励
    function rewardDelegator(address proposer, uint256 amountTotal) internal {
        Staking sc = Staking(stakingAddress);

        // 获取所有质押者地址
        address[] memory delegators = sc.getDelegators(proposer);

        // 计算delegator总质押额
        uint256 delegateTotal;
        for (uint256 i = 0; i < delegators.length; i++) {
            delegateTotal += sc.getDelegateAmount(proposer, delegators[i]);
        }

        // 按照质押比例发放奖励
        uint256 rewardAmount;
        for (uint256 i = 0; i < delegators.length; i++) {
            rewardAmount =
                (sc.getDelegateAmount(proposer, delegators[i]) * amountTotal) /
                delegateTotal;
            rewardAmount = (rewardAmount / (10**12)) * (10**12);

            sc.addDelegateAmountAndPower(proposer, delegators[i], rewardAmount);

            emit Rewards(delegators[i], rewardAmount);
        }
    }
}
