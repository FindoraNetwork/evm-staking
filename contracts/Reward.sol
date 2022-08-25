// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Staking.sol";
import "./interfaces/ISystem.sol";
import "./interfaces/IBase.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Reward is Initializable, AccessControlEnumerable, IBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM");

    // Staking contract address
    address public stakingAddress;
    // Power contract address
    address public powerAddress;

    // Punish rate
    uint256 private duplicateVotePunishRate;
    uint256 private lightClientAttackPunishRate;
    uint256 private offLinePunishRate;
    uint256 private unknownPunishRate;

    // (reward address => reward amount)
    mapping(address => uint256) public rewords;

    // Claim data
    ClaimOps[] public claimOps;

    /*
     *  APY：delegator return_rate records
     * (height => reward rate)
     */
    mapping(uint256 => uint256[2]) public returnRateRecords;

    struct PunishInfo {
        address validator;
        ByztineBehavior behavior;
        uint256 power;
    }

    event Punish(
        address punishAddress,
        ByztineBehavior behavior,
        uint256 amount
    );
    event Rewards(address rewardAddress, uint256 amount);
    event Claim(address claimAddress, uint256 amount);

    function initialize(
        uint256 duplicateVotePunishRate_,
        uint256 lightClientAttackPunishRate_,
        uint256 offLinePunishRate_,
        uint256 unknownPunishRate_,
        address stakingAddress_,
        address powerAddress_
    ) public initializer {
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

    // Claim assets
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
        // Validator/Proposer return_rate
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
        // 质押金额total_amount（当前validator相关）：validator质押金额 + 其旗下delegator质押金额
        // 质押金额am：当前delegator的质押金额
        // return_rate 分为两种，分别在上面已经计算
        // 计算公式：(am / total_amount) * (global_amount * ((return_rate[0] / return_rate[1]) / ((365 * 24 * 3600) / block_itv)))

        // 解决栈太深，所以赋值新变量
        address validatorCopy = validator;
        // 当前validator及旗下所有delegator质押金额
        uint256 total_amount;
        // 整个系统质押总额
        uint256 global_amount = sc.delegateTotal();
        // 出块周期
        uint256 blockInterval = sc.blockInterval();
        // 计算质押金额
        address[] memory delegators = sc.getDelegatorsByValidator(
            validatorCopy
        );
        for (uint256 i = 0; i < delegators.length; i++) {
            total_amount += sc.getDelegateAmount(validatorCopy, delegators[i]);
        }

        // 给proposer所有的delegator发放奖励,并返回所有delegator的总佣金
        uint256 totalCommission;
        totalCommission = rewardDelegator(
            validatorCopy,
            delegators,
            total_amount,
            global_amount,
            delegatorReturnRate,
            blockInterval
        );

        // 给proposer发放奖

        uint256 am = sc.getStakerDelegateAmount(validatorCopy);
        // 当前validator的staker地址
        address stakerAddress = sc.getStakerByValidator(validatorCopy);
        am +=
            (rewords[validatorCopy] * am) /
            sc.getDelegateTotalAmount(stakerAddress);

        uint256 proposerRewards = (am / total_amount) *
            (global_amount *
                ((returnRateProposer[0] / returnRateProposer[1]) /
                    ((365 * 24 * 3600) / blockInterval)));

        // proposer奖励 = 公式计算结果+旗下所有delegator的佣金
        rewords[validatorCopy] += proposerRewards + totalCommission;

        emit Rewards(validatorCopy, proposerRewards);
    }

    function descSort(PunishInfo[] memory punishInfo)
        internal
        pure
        returns (PunishInfo[] memory)
    {
        for (uint256 i = 0; i < punishInfo.length - 1; i++) {
            for (uint256 j = 0; j < punishInfo.length - 1 - i; j++) {
                if (punishInfo[j].power < punishInfo[j + 1].power) {
                    PunishInfo memory temp = punishInfo[j];
                    punishInfo[j] = punishInfo[j + 1];
                    punishInfo[j + 1] = temp;
                }
            }
        }
        return punishInfo;
    }

    // Punish validator and delegators
    function punish(
        address[] memory signed,
        address[] memory byztine,
        ByztineBehavior[] memory behavior,
        uint256 validatorSetMaximum
    ) public onlyRole(SYSTEM_ROLE) {
        // Staking 合约对象
        Staking stakingContract = Staking(stakingAddress);
        // Power 合约对象
        Power powerContract = Power(stakingAddress);
        // Punish rate
        uint256[2] memory punishRate;
        // validator 质押金额
        uint256 validatorDelegateAmount;
        // validator 被处罚金额
        uint256 validatorPunishAmount;
        // 解决栈太深，重新赋值新变量
        address[] memory byztineCopy = byztine;
        // 被处罚的validator信息（账户地址、处罚金额，被处罚行为）
        PunishInfo[] memory punishInfo;
        // punishInfo 数组索引
        uint256 punishInfoIndex;
        // 被处罚的validator信息（已做好降序排列，并且根据数量限制去除无效处罚信息）
        PunishInfo[] memory punishInfoRes;
        for (uint256 i = 0; i < byztineCopy.length; i++) {
            // Check whether the byztine is a validator
            if (!stakingContract.isValidator(byztineCopy[i])) {
                continue;
            }

            punishInfo[punishInfoIndex] = PunishInfo(
                byztineCopy[i],
                behavior[i],
                powerContract.getPower(byztineCopy[i])
            );

            punishInfoIndex++;
        }
        // 按照质押金额倒叙重排
        punishInfo = descSort(punishInfo);
        // 如果处罚信息数量过大，去掉多余处罚信息
        // punishInfo.length = validatorSetMaximum; 报错了，貌似只适合bytes字节数组，暂时换回下面方式
        for (uint256 a = 0; a < punishInfo.length; a++) {
            if (a >= validatorSetMaximum) {
                break;
            }
        }

        bool isOnLine;
        address[] memory signedValidators = signed;
        // 解决栈太深，重新赋值新变量
        Staking sc = Staking(stakingAddress);
        for (uint256 i = 0; i < punishInfoRes.length; i++) {
            // 计算punish rate
            {
                for (uint256 h = 0; h < signedValidators.length; h++) {
                    if (signedValidators[h] == punishInfoRes[i].validator) {
                        isOnLine = true;
                    }
                }
                punishRate = getPunishRate(punishInfoRes[i].behavior, isOnLine);
            }

            // 解决栈太深，重新赋值新变量
            uint256[2] memory delegatorPunishRate = punishRate;

            // 处罚 validator
            validatorDelegateAmount = sc.getDelegateAmount(
                punishInfoRes[i].validator,
                punishInfoRes[i].validator
            );
            validatorPunishAmount =
                (validatorDelegateAmount * punishRate[0]) /
                punishRate[1];
            sc.descDelegateAmountAndPower(
                punishInfoRes[i].validator,
                punishInfoRes[i].validator,
                validatorPunishAmount
            );

            emit Punish(
                punishInfoRes[i].validator,
                punishInfoRes[i].behavior,
                validatorPunishAmount
            );

            // 处罚validator的delegators
            address[] memory delegators = sc.getDelegatorsByValidator(
                punishInfoRes[i].validator
            );
            // 质押金额
            uint256 delegateAmount;
            // 处罚金额
            uint256 punishAmount;
            // 实际处罚金额
            uint256 realPunishAmount;

            for (uint256 j = 0; j < delegators.length; j++) {
                delegateAmount = sc.getDelegateAmount(
                    delegators[j],
                    punishInfoRes[i].validator
                );
                punishAmount =
                    (delegateAmount * delegatorPunishRate[0]) /
                    delegatorPunishRate[1];

                // 处罚金额小于质押金额
                realPunishAmount = punishAmount;
                if (punishAmount > (delegateAmount + rewords[delegators[j]])) {
                    // 处罚金额大于质押金额和奖励金额之和，就将质押金额和奖励金额清零
                    realPunishAmount = delegateAmount + rewords[delegators[j]];
                    rewords[delegators[j]] = 0;
                } else if (punishAmount > delegateAmount) {
                    // 处罚金额大于质押金额，就将质押金额清零,然后扣除一部分奖励
                    realPunishAmount = punishAmount;
                    rewords[delegators[j]] -= punishAmount - delegateAmount;
                }

                sc.descDelegateAmountAndPower(
                    punishInfoRes[i].validator,
                    delegators[j],
                    realPunishAmount
                );

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
            // 判断 签名地址是否是 validator
            if (sc.isValidator(signed[i])) {
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
    function getPunishRate(ByztineBehavior byztineBehavior, bool isOnLine)
        internal
        view
        returns (uint256[2] memory)
    {
        uint256[2] memory punishRate;
        if (!isOnLine) {
            punishRate = [offLinePunishRate, 10**18];
        } else if (byztineBehavior == ByztineBehavior.DuplicateVote) {
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
        address[] memory delegatorsOfValidator,
        uint256 total_amount,
        uint256 global_amount,
        uint256[2] memory returnRate,
        uint256 blockInterval
    ) internal returns (uint256) {
        Staking sc = Staking(stakingAddress);

        // 佣金比例
        uint256 commissionRate = sc.getValidatorRate(proposer);
        //
        uint256 am;
        // 佣金
        uint256 commission;
        // 按照质押比例给某个delegator发放的奖励金额
        uint256 delegatorReward;
        // 按照质押比例给某个delegator，减去佣金后实际发放的奖励金额
        uint256 delegatorRealReward;
        // 为了解决栈太深，重新赋值新变量
        address validator = proposer;
        // 所有delegator的总佣金
        uint256 totalCommission;

        // 重新赋值新变量，解决栈太深
        address[] memory delegators = delegatorsOfValidator;
        for (uint256 i = 0; i < delegators.length; i++) {
            am = sc.getDelegateAmount(validator, delegators[i]);
            // (d.reward * am)/d.amount(delegator所有的质押金额)
            am +=
                (rewords[delegators[i]] * am) /
                sc.getDelegateTotalAmount(delegators[i]);
            // 带佣金的奖励
            delegatorReward =
                (am / total_amount) *
                (global_amount *
                    ((returnRate[0] / returnRate[1]) /
                        ((365 * 24 * 3600) / blockInterval)));
            // 佣金，佣金给到这个validator的self-delegator的delegation之中
            commission = delegatorReward * commissionRate;
            totalCommission += commission;
            // 实际分配给delegator的奖励， 奖励需要按佣金比例扣除佣金,最后剩下的才是奖励
            delegatorRealReward = delegatorReward - commission;
            // 格式化奖励金额，将后12位置为0
            delegatorRealReward = (delegatorRealReward / (10**12)) * (10**12);
            // 增加delegator reward金额
            rewords[delegators[i]] += delegatorRealReward;

            // 事件日志
            emit Rewards(delegators[i], delegatorRealReward);
        }
        return totalCommission;
    }
}
