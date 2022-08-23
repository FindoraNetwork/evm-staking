// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Staking.sol";
import "./interfaces/ISystem.sol";
import "./interfaces/IBase.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract Reward is AccessControlEnumerable, IBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM");

    // Staking contract address
    address public stakingAddress;
    // Power contract address
    address public powerAddress;

    // Validator-info set Maximum length
    uint256 public validatorSetMaximum;

    // Punish rate
    uint256 private duplicateVotePunishRate;
    uint256 private lightClientAttackPunishRate;
    uint256 private offLinePunishRate;
    uint256 private unknownPunishRate;

    // (reward address => reward amount)
    mapping(address => uint256) public rewords;

    // Claim data
    ClaimOps[] public claimOps;

    // (height => reward rate records)
    mapping(uint256 => uint256[2]) public returnRateRecords;

    struct PunishInfo {
        address validator;
        ByztineBehavior behavior;
        uint256 stakingAmount;
    }

    event Punish(
        address punishAddress,
        ByztineBehavior behavior,
        uint256 amount
    );
    event Rewards(address rewardAddress, uint256 amount);
    event Claim(address claimAddress, uint256 amount);

    constructor(
        uint256 duplicateVotePunishRate_,
        uint256 lightClientAttackPunishRate_,
        uint256 offLinePunishRate_,
        uint256 unknownPunishRate_,
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

    function adminSetDuplicateVotePunishRate(uint256 duplicateVotePunishRate_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        duplicateVotePunishRate = duplicateVotePunishRate_;
    }

    function adminSetLightClientAttackPunishRate(
        uint256 lightClientAttackPunishRate_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        lightClientAttackPunishRate = lightClientAttackPunishRate_;
    }

    function adminSetOffLinePunishRate(uint256 offLinePunishRate_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        offLinePunishRate = offLinePunishRate_;
    }

    function adminSetUnknownPunishRate(uint256 unknownPunishRate_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        unknownPunishRate = unknownPunishRate_;
    }

    function claim(address delegator, uint256 amount) external {
        require(rewords[delegator] >= amount, "insufficient amount");
        rewords[delegator] -= amount;
        claimOps.push(ClaimOps(delegator, amount));
    }

    // Get the data currently claiming
    function GetClaimOps()
        public
        view
        onlyRole(SYSTEM_ROLE)
        returns (ClaimOps[] memory)
    {
        return claimOps;
    }

    // Clear the data currently claiming
    function clearClaimOps() public onlyRole(SYSTEM_ROLE) {
        delete claimOps;
    }

    // Distribute rewards
    function reward(
        address validator, // proposer
        address[] memory signed,
        uint256 circulationAmount //
    ) public onlyRole(SYSTEM_ROLE) {
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
        // 质押金额am：当前delegator的质押金额
        // return_rate 分为两种，分别在上面已经计算
        // 计算公式：(am / total_amount) * (global_amount * ((return_rate[0] / return_rate[1]) / ((365 * 24 * 3600) / block_itv)))

        // 解决栈太深，所以赋值新变量
        address staker = validator;
        // 当前staker及旗下所有delegator质押金额
        uint256 total_amount;
        // 整个系统质押总额
        uint256 global_amount = sc.delegateTotal();
        // 出块周期
        uint256 blockInterval = sc.blockInterval();
        // 计算质押金额
        total_amount += sc.getDelegateAmount(staker, staker);
        address[] memory delegators = sc.getDelegators(staker);
        for (uint256 i = 0; i < delegators.length; i++) {
            total_amount += sc.getDelegateAmount(staker, delegators[i]);
        }

        // 给proposer所有的delegator发放奖励
        rewardDelegator(
            staker,
            delegators,
            total_amount,
            global_amount,
            delegatorReturnRate,
            blockInterval
        );

        // 给proposer发放奖
        uint256 am = sc.getDelegateAmount(staker, staker);
        uint256 proposerRewards = (am / total_amount) *
            (global_amount *
                ((returnRateProposer[0] / returnRateProposer[1]) /
                    ((365 * 24 * 3600) / blockInterval)));

        rewords[staker] += proposerRewards;

        emit Rewards(staker, proposerRewards);
    }

    function descSort(PunishInfo[] memory punishInfo)
        internal
        pure
        returns (PunishInfo[] memory)
    {
        for (uint256 i = 0; i < punishInfo.length - 1; i++) {
            for (uint256 j = 0; j < punishInfo.length - 1 - i; j++) {
                if (
                    punishInfo[j].stakingAmount <
                    punishInfo[j + 1].stakingAmount
                ) {
                    PunishInfo memory temp = punishInfo[j];
                    punishInfo[j] = punishInfo[j + 1];
                    punishInfo[j + 1] = temp;
                }
            }
        }
        return punishInfo;
    }

    // Punish validator and delegators
    function punish(address[] memory byztine, ByztineBehavior[] memory behavior)
        public
        onlyRole(SYSTEM_ROLE)
    {
        // Staking 合约对象
        Staking sc = Staking(stakingAddress);
        // Punish rate
        uint256[2] memory punishRate;
        // staker 质押金额
        uint256 stakerDelegateAmount;
        // staker 被处罚金额
        uint256 stakerPunishAmount;
        // byztine账户地址数组（去除掉不是staker的byztine）
        address[] memory byztineSatisfy = byztine;
        // 被处罚的staker信息（账户地址、处罚金额，被处罚行为）
        PunishInfo[] memory punishInfo;
        // punishInfo 数组索引
        uint256 punishInfoIndex;
        // 被处罚的staker信息（已做好降序排列，并且根据数量限制去除无效处罚信息）
        PunishInfo[] memory punishInfoRes;
        for (uint256 i = 0; i < byztineSatisfy.length; i++) {
            // Check whether the byztine is a stacker
            if (!sc.isStaker(byztineSatisfy[i])) {
                continue;
            }

            punishInfo[punishInfoIndex] = PunishInfo(
                byztine[i],
                behavior[i],
                sc.getDelegateAmount(byztineSatisfy[i], byztineSatisfy[i])
            );
            punishInfoIndex++;
        }
        // 按照质押金额倒叙重排
        punishInfo = descSort(punishInfo);
        // 如果处罚信息数量过大，去掉多余处罚信息
        for (uint256 i = 0; i < punishInfo.length; i++) {
            if (i >= validatorSetMaximum) {
                break;
            }
            punishInfoRes[i] = punishInfo[i];
        }

        uint256 power;
        for (uint256 i = 0; i < punishInfoRes.length; i++) {
            punishRate = getPunishRate(punishInfoRes[i].behavior);

            // 处罚 staker

            stakerDelegateAmount = sc.getDelegateAmount(
                punishInfoRes[i].validator,
                punishInfoRes[i].validator
            );
            power =
                ((stakerDelegateAmount * punishRate[0]) / punishRate[1]) /
                (10**12);
            stakerPunishAmount = power * (10**12);
            sc.descDelegateAmountAndPower(
                punishInfoRes[i].validator,
                punishInfoRes[i].validator,
                stakerPunishAmount
            );

            emit Punish(
                punishInfoRes[i].validator,
                punishInfoRes[i].behavior,
                stakerPunishAmount
            );

            // 处罚staker的delegators
            address[] memory delegators = sc.getDelegators(
                punishInfoRes[i].validator
            );
            uint256 delegateAmount;
            uint256 punishAmount;
            uint256 realPunishAmount;
            for (uint256 j = 0; j < delegators.length; j++) {
                delegateAmount = sc.getDelegateAmount(
                    delegators[j],
                    punishInfoRes[i].validator
                );
                power =
                    ((delegateAmount * punishRate[0]) / punishRate[1]) /
                    (10**12);
                punishAmount = power * (10**12);

                if (punishAmount > (delegateAmount + rewords[delegators[j]])) {
                    // 处罚金额大于质押金额和奖励金额之和，就将质押金额和奖励金额清零
                    realPunishAmount = delegateAmount + rewords[delegators[j]];
                    sc.descDelegateAmountAndPower(
                        punishInfoRes[i].validator,
                        delegators[j],
                        delegateAmount
                    );
                    rewords[delegators[j]] = 0;
                } else if (punishAmount > delegateAmount) {
                    // 处罚金额大于质押金额，就将质押金额清零,然后扣除一部分奖励
                    realPunishAmount = punishAmount;
                    sc.descDelegateAmountAndPower(
                        punishInfoRes[i].validator,
                        delegators[j],
                        delegateAmount
                    );
                    rewords[delegators[j]] -= punishAmount - delegateAmount;
                } else {
                    // 处罚金额小于于质押金额，就将质押金额扣除处罚金额
                    realPunishAmount = punishAmount;
                    sc.descDelegateAmountAndPower(
                        punishInfoRes[i].validator,
                        delegators[j],
                        punishAmount
                    );
                }

                emit Punish(
                    delegators[j],
                    punishInfoRes[i].behavior,
                    realPunishAmount
                );
            }
        }
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
    function getPunishRate(ByztineBehavior byztineBehavior)
        internal
        view
        returns (uint256[2] memory)
    {
        uint256[2] memory punishRate;
        if (byztineBehavior == ByztineBehavior.DuplicateVote) {
            punishRate = [duplicateVotePunishRate, 10**18];
        } else if (byztineBehavior == ByztineBehavior.LightClientAttack) {
            punishRate = [lightClientAttackPunishRate, 10**18];
        } else if (byztineBehavior == ByztineBehavior.Unknown) {
            punishRate = [unknownPunishRate, 10**18];
        }

        return punishRate;
    }

    // 给proposer所有的delegator发放奖励
    function rewardDelegator(
        address proposer,
        address[] memory delegatorOfStaker,
        uint256 total_amount,
        uint256 global_amount,
        uint256[2] memory returnRate,
        uint256 blockInterval
    ) internal {
        Staking sc = Staking(stakingAddress);

        // 佣金比例
        uint256 commissionRate = sc.getStakerRate(proposer);

        // 某个delegator质押金额
        uint256 am;
        // 佣金
        uint256 commission;
        // 按照质押比例给某个delegator发放的奖励金额
        uint256 delegatorReward;
        // 按照质押比例给某个delegator，减去佣金后实际发放的奖励金额
        uint256 delegatorRealReward;

        address staker = proposer;

        address[] memory delegators = delegatorOfStaker;
        for (uint256 i = 0; i < delegators.length; i++) {
            am = sc.getDelegateAmount(staker, delegators[i]);

            delegatorReward =
                (am / total_amount) *
                (global_amount *
                    ((returnRate[0] / returnRate[1]) /
                        ((365 * 24 * 3600) / blockInterval)));

            // 佣金，佣金给到这个validator的self-delegator的delegation之中
            commission = delegatorReward * commissionRate;

            // 实际分配给delegator的奖励， 奖励需要按佣金比例扣除佣金,最后剩下的才是奖励
            delegatorRealReward = delegatorReward - commission;
            // 格式化奖励金额，将后12为置为0
            delegatorRealReward = (delegatorRealReward / (10**12)) * (10**12);

            // 增加delegator reward金额
            rewords[delegators[i]] += delegatorRealReward;

            // 事件日志
            emit Rewards(delegators[i], delegatorRealReward);
        }
    }
}
