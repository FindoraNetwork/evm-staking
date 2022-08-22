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

    // Punish rate
    uint256[2] private duplicateVotePunishRate;
    uint256[2] private lightClientAttackPunishRate;
    uint256[2] private offLinePunishRate;
    uint256[2] private unknownPunishRate;

    // (reward address => reward amount)
    mapping(address => uint256) public rewords;

    // Claim data
    mapping(address => uint256) public claimingOps;
    EnumerableSet.AddressSet private claimingAddressSet;

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

    // claim模块逻辑：
    // claim信息：当前claim的账户地址和对应金额的信息
    // 1 用户claim操作生成claim信息
    // 2 系统调用system合约查询当前claim信息，然后通过coinbase发钱。
    // 3 这里假定系统拿到账户地址和金额后可以百分百打款成功，那拿到信息后就清除claim信息，然后结束。
    function claim(address validator, uint256 amount) external {
        require(rewords[validator] >= amount, "insufficient amount");
        claimingAddressSet.add(validator);
        claimingOps[validator] += amount;
        rewords[validator] -= amount;
        if (rewords[validator] == 0) {
            delete rewords[validator];
        }
    }

    // Clear the data currently claiming
    function clearClaimOps(address[] memory validators) public {
        for (uint256 i = 0; i < validators.length; i++) {
            claimingAddressSet.remove(validators[i]);
        }
    }

    // Get accounts currently claiming
    function getClaimAccounts() public view returns (address[] memory) {
        return claimingAddressSet.values();
    }

    // Get amount currently claiming
    function getClaimAmount(address account) public view returns (uint256) {
        return claimingOps[account];
    }

    // Distribute rewards
    function reward(
        address validator, // proposer
        address[] memory signed,
        uint256 circulationAmount
    ) public {
        uint256[2] memory returnRateProposer;
        // Staker return_rate
        returnRateProposer = lastVotePercent(signed);

        Staking sc = Staking(stakingAddress);
        uint256 totalDelegationAmount = sc.delegateTotal();

        // APY：delegator return_rate
        uint256[2] memory delegatorReturnRate;
        delegatorReturnRate = getBlockReturnRate(
            totalDelegationAmount,
            circulationAmount
        );
        returnRateRecords[block.number] = delegatorReturnRate;

        // 质押金额global_amount：所有用户质押金额
        // 质押金额total_amount（当前staker相关）：staker质押金额 + 其旗下delegator质押金额
        // 质押金额am：当前staker旗下delegator质押金额
        // return_rate 分为两种，分别在上面已经计算
        // 计算公式：(am / total_amount) * (global_amount * ((return_rate[0] / return_rate[1]) / ((365 * 24 * 3600) / block_itv)))
        address staker = validator;
        uint256 am;
        uint256 total_amount;
        uint256 delegateAmount;
        uint256 delegatorRewards;
        uint256 blockInterval = sc.blockInterval();
        // 所有用户质押金额 global_amount
        uint256 global_amount = sc.delegateTotal();
        // 获取staker质押金额
        total_amount += sc.getDelegateAmount(staker, staker);
        // 获取staker旗下所有delegator质押金额
        address[] memory delegators = sc.getDelegators(staker);
        for (uint256 i = 0; i < delegators.length; i++) {
            delegateAmount = sc.getDelegateAmount(staker, delegators[i]);
            am += delegateAmount;
            total_amount += delegateAmount;
        }

        // 给proposer所有的delegator发放奖励
        {
            delegatorRewards =
                (am / total_amount) *
                (global_amount *
                    ((delegatorReturnRate[0] / delegatorReturnRate[1]) /
                        ((365 * 24 * 3600) / blockInterval)));

            // 佣金比例
            uint256 commissionRate = sc.getStakerRate(staker);
            // 佣金，佣金给到这个validator的self-delegator的delegation之中
            uint256 commission = delegatorRewards * commissionRate;
            // 实际分配给delegator的奖励， 奖励需要按佣金比例扣除佣金,最后剩下的才是奖励
            uint256 delegatorRealReward = delegatorRewards - commission;
            // 给proposer所有的delegator发放奖励
            rewardDelegator(staker, delegatorRealReward);
        }

        // 给proposer发放奖
        uint256 proposerRewards = (am / total_amount) *
            (global_amount *
                ((returnRateProposer[0] / returnRateProposer[1]) /
                    ((365 * 24 * 3600) / blockInterval)));

        sc.addDelegateAmountAndPower(staker, staker, proposerRewards);
        rewords[staker] += proposerRewards;

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

            emit Punish(validator, behavior[i], stakerPunishAmount);

            // Punish delegators
            address[] memory delegators = sc.getDelegators(validator);
            uint256 delegateAmount;
            uint256 punishAmount;
            uint256 realPunishAmount;
            for (uint256 j = 0; j < delegators.length; j++) {
                delegateAmount = sc.getDelegateAmount(delegators[j], validator);
                power =
                    ((delegateAmount * punishRate[0]) / punishRate[1]) /
                    (10**12);
                punishAmount = power * (10**12);
                // 假如这里用户amount不足，又不能让它触发require，导致后面停止执行那就给他余额减为0 ？
                if (punishAmount > delegateAmount) {
                    realPunishAmount = delegateAmount;
                } else {
                    realPunishAmount = punishAmount;
                }
                sc.descDelegateAmountAndPower(
                    validator,
                    delegators[j],
                    realPunishAmount
                );

                emit Punish(delegators[j], behavior[i], realPunishAmount);
            }
        }

        // 先检查一遍 staker和delegator的金额和power是否充足，然后再做减操作，后面需要再检查
        // 对于 本金-惩罚金额,本金不足扣奖励 这条规则，当前本金和奖励都会加到staking合约的amount，所以不用考虑
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
            // 判断 签名地址是否是 staker
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

    // Get punish rate
    function getPunishInfo(ByztineBehavior byztineBehavior)
        internal
        view
        returns (uint256[2] memory)
    {
        uint256[2] memory punishRate;
        if (byztineBehavior == ByztineBehavior.DuplicateVote) {
            punishRate = duplicateVotePunishRate;
        } else if (byztineBehavior == ByztineBehavior.LightClientAttack) {
            punishRate = lightClientAttackPunishRate;
        } else if (byztineBehavior == ByztineBehavior.Unknown) {
            punishRate = unknownPunishRate;
        }

        return punishRate;
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
            // 计算reward金额
            rewardAmount =
                (sc.getDelegateAmount(proposer, delegators[i]) * amountTotal) /
                delegateTotal;
            rewardAmount = (rewardAmount / (10**12)) * (10**12);

            // 增加delegator staking金额和power
            sc.addDelegateAmountAndPower(proposer, delegators[i], rewardAmount);

            // 增加delegator reward金额
            rewords[delegators[i]] += rewardAmount;

            // 事件日志
            emit Rewards(delegators[i], rewardAmount);
        }
    }
}
