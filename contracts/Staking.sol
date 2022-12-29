// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IStaking.sol";
import "./interfaces/IBase.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Staking is
    Initializable,
    AccessControlEnumerableUpgradeable,
    IBase,
    IStaking
{
    using AddressUpgradeable for address;
    using AddressUpgradeable for address payable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using SafeMathUpgradeable for uint256;

    /// --- contract config for Staking ---

    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM");
    bytes32 public constant POWER_ROLE = keccak256("POWER_ROLE");
    uint256 public constant FRA_UNITS = 10 ** 6;

    /// --- End contract config for staking ---

    /// --- Configure

    // Mininum staking value; Default: 10000 FRA
    uint256 public stakeMininum;

    function adminSetStakeMinimum(
        uint256 stakeMininum_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        stakeMininum = stakeMininum_;
    }

    // Mininum delegate value; Default 1 unit
    uint256 public delegateMininum;

    function adminSetDelegateMinimum(
        uint256 delegateMininum_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        delegateMininum = delegateMininum_;
    }

    // rate of power. decimal is 6
    uint256 public powerRateMaximum;

    function adminSetPowerRateMaximum(
        uint256 powerRateMaximum_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        powerRateMaximum = powerRateMaximum_;
    }

    // blocktime; Default 16.
    uint256 public blocktime;

    function adminSetBlocktime(
        uint256 blocktime_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        blocktime = blocktime_;
    }

    // unbound block count; Default 21 day. (21 * 24 * 60 * 60 / 16)
    uint256 public unboundBlock;

    function adminUnboundBlock(
        uint256 unboundBlock_
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        unboundBlock = unboundBlock_;
    }

    /// --- End Configure

    /// --- State of validator

    struct Validator {
        // Public key of validator
        bytes public_key;
        // Public key type
        PublicKeyType ty;
        // memo of validator
        string memo;
        // rate of validator, decimal is 6
        uint256 rate;
        // address of staker
        address staker;
        uint256 power;
        uint256 beginBlock;
    }

    // address of tendermint => validator
    mapping(address => Validator) public validators;

    // Addresses of all validators
    EnumerableSetUpgradeable.AddressSet private allValidators;

    function allValidatorsLength() public view returns (uint256) {
        return allValidators.length();
    }

    function allValidatorsAt(uint256 idx) public view returns (address) {
        return allValidators.at(idx);
    }

    function allValidatorsContains(address value) public view returns (bool) {
        return allValidators.contains(value);
    }

    /// --- End State of validator

    /// --- State of delegator

    struct Delegator {
        mapping(address => uint256) boundAmount;
        mapping(address => uint256) unboundAmount;
        uint256 amount;
    }

    mapping(address => Delegator) public delegators;

    function delegatorsBoundAmount(
        address delegator,
        address validator
    ) public view returns (uint256) {
        return delegators[delegator].boundAmount[validator];
    }

    function delegatorsUnboundAmount(
        address delegator,
        address validator
    ) public view returns (uint256) {
        return delegators[delegator].unboundAmount[validator];
    }

    mapping(address => EnumerableSetUpgradeable.AddressSet)
        private delegatorOfValidator;

    mapping(address => EnumerableSetUpgradeable.AddressSet)
        private validatorOfDelegator;

    EnumerableSetUpgradeable.AddressSet private allDelegators;

    function _addDelegator(
        address delegator,
        address validator,
        uint256 amount
    ) private {
        Delegator storage d = delegators[delegator];

        uint256 boundAmount = d.boundAmount[validator];
        d.boundAmount[validator] = boundAmount.add(amount);

        d.amount = d.amount.add(amount);

        Validator storage v = validators[validator];
        v.power = v.power.add(amount);

        delegatorOfValidator[delegator].add(validator);
        validatorOfDelegator[validator].add(delegator);

        totalDelegationAmount = totalDelegationAmount.add(amount);

        allDelegators.add(delegator);
    }

    function _delDelegator(
        address delegator,
        address validator,
        uint256 amount
    ) private {
        Delegator storage d = delegators[delegator];

        uint256 boundAmount = d.boundAmount[validator];
        d.boundAmount[validator] = boundAmount.sub(amount);

        uint256 unboundAmount = d.unboundAmount[validator];
        d.unboundAmount[validator] = unboundAmount.add(amount);
    }

    function _realDelDelegator(
        address delegator,
        address validator,
        uint256 amount
    ) private {
        Delegator storage d = delegators[delegator];

        uint256 unboundAmount = d.unboundAmount[validator];
        d.unboundAmount[validator] = unboundAmount.sub(amount);

        if (d.unboundAmount[validator] + d.boundAmount[validator] == 0) {
            delegatorOfValidator[delegator].remove(validator);
            validatorOfDelegator[validator].remove(delegator);
        }

        d.amount = d.amount.sub(amount);

        Validator storage v = validators[validator];
        v.power = v.power.sub(amount);

        if (v.power == 0) {
            delete validators[validator];
            allValidators.remove(validator);
        }

        totalDelegationAmount = totalDelegationAmount.sub(amount);
    }

    function delegatorOfValidatorLength(
        address delegator
    ) public view returns (uint256) {
        return delegatorOfValidator[delegator].length();
    }

    function delegatorOfValidatorAt(
        address delegator,
        uint256 idx
    ) public view returns (address) {
        return delegatorOfValidator[delegator].at(idx);
    }

    function delegatorOfValidatorContains(
        address delegator,
        address value
    ) public view returns (bool) {
        return delegatorOfValidator[delegator].contains(value);
    }

    function validatorOfDelegatorLength(
        address validator
    ) public view returns (uint256) {
        return validatorOfDelegator[validator].length();
    }

    function validatorOfDelegatorAt(
        address validator,
        uint256 idx
    ) public view returns (address) {
        return validatorOfDelegator[validator].at(idx);
    }

    function validatorOfDelegatorContains(
        address validator,
        address value
    ) public view returns (bool) {
        return validatorOfDelegator[validator].contains(value);
    }

    function allDelegatorsLength() public view returns (uint256) {
        return allDelegators.length();
    }

    function allDelegatorsAt(uint256 idx) public view returns (address) {
        return allDelegators.at(idx);
    }

    function allDelegatorsContains(address value) public view returns (bool) {
        return allDelegators.contains(value);
    }

    /// --- End state of delegator

    /// --- State of total staking

    // Total amount of delegate
    uint256 public totalDelegationAmount;

    function maxDelegationAmountBasedOnTotalAmount()
        public
        view
        returns (uint256)
    {
        return (totalDelegationAmount * powerRateMaximum) / FRA_UNITS;
    }

    /// --- End state of total staking

    /// --- State of undelegation

    struct UndelegationInfo {
        address validator;
        address payable delegator;
        uint256 amount;
        uint256 height;
    }

    mapping(bytes32 => UndelegationInfo) public undelegations;

    EnumerableSetUpgradeable.Bytes32Set allUndelegations;

    /// --- End state of undelegation

    /// --- Record for delegate and undelegate

    // enum RecordType {
    //     Unknown,
    //     Delegate,
    //     Undelegate
    // }

    // struct Record {
    //     uint256 height;
    //     address validator;
    //     address delegator;
    //     uint256 amount;
    //     RecordType ty;
    // }

    // mapping(address => bytes32[]) public delegatorRecordIndex;

    // function delegatorRecordIndexLength(address delegator)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     return delegatorRecordIndex[delegator].length;
    // }

    // mapping(bytes32 => Record) public records;

    /// --- End record for delegate and undelegate

    event Stake(
        address indexed validator,
        bytes public_key,
        PublicKeyType ty,
        address indexed staker,
        uint256 amount,
        string memo,
        uint256 rate
    );
    event Delegation(
        address indexed validator,
        address indexed delegator,
        uint256 amount
    );
    event Undelegation(
        address indexed validator,
        address indexed receiver,
        uint256 amount
    );

    function initialize(address system_) public initializer {
        stakeMininum = 10000 * FRA_UNITS;
        delegateMininum = 1;
        powerRateMaximum = 200000;
        blocktime = 16;
        unboundBlock = (21 * 24 * 60 * 60) / 16;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SYSTEM_ROLE, system_);
    }

    // Stake
    function stake(
        address validator,
        bytes calldata public_key,
        string calldata memo,
        uint256 rate
    ) external payable override {
        // Check whether the validator was staked
        require(validators[validator].staker == address(0), "already staked");

        uint256 amount = dropAmount(msg.value, 12);

        require(amount * (10 ** 12) == msg.value, "lower 12 must be 0.");

        require(amount >= stakeMininum, "amount too small");

        uint256 maxDelegateAmount = maxDelegationAmountBasedOnTotalAmount();

        require(amount <= maxDelegateAmount, "amount too large");

        PublicKeyType ty = PublicKeyType.Ed25519;

        Validator storage v = validators[validator];
        v.public_key = public_key;
        v.memo = memo;
        v.rate = rate;
        v.staker = msg.sender;
        v.beginBlock = block.number;
        v.ty = ty;

        allValidators.add(validator);

        _addDelegator(msg.sender, validator, amount);

        // /// record delegate
        // bytes32 idx = keccak256(
        //     abi.encode(block.number, validator, msg.sender, amount, uint256(1))
        // );

        // Record storage r = records[idx];
        // r.height = block.number;
        // r.validator = validator;
        // r.delegator = msg.sender;
        // r.amount = amount;
        // r.ty = RecordType.Delegate;

        // delegatorRecordIndex[msg.sender].push(idx);

        emit Stake(
            validator,
            public_key,
            ty,
            msg.sender,
            msg.value,
            memo,
            rate
        );
    }

    // Delegate assets
    function delegate(address validator) external payable override {
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator");

        uint256 amount = dropAmount(msg.value, 12);

        require(amount * (10 ** 12) == msg.value, "lower 12 must be 0.");

        require(amount >= delegateMininum, "amount is too small");

        uint256 maxDelegateAmount = maxDelegationAmountBasedOnTotalAmount();

        require(amount <= maxDelegateAmount, "amount too large");

        _addDelegator(msg.sender, validator, amount);

        // /// record delegate
        // bytes32 idx = keccak256(
        //     abi.encode(block.number, validator, msg.sender, amount, uint256(1))
        // );

        // Record storage r = records[idx];
        // r.height = block.number;
        // r.validator = validator;
        // r.delegator = msg.sender;
        // r.amount = amount;
        // r.ty = RecordType.Delegate;

        // delegatorRecordIndex[msg.sender].push(idx);

        emit Delegation(validator, msg.sender, amount);
    }

    // UnDelegate assets
    function undelegate(address validator, uint256 amount) external override {
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator");

        require(amount > 0, "amount must be greater than 0");

        Delegator storage d = delegators[msg.sender];
        require(
            amount <= d.boundAmount[validator],
            "amount greater than bound amount"
        );

        _delDelegator(msg.sender, validator, amount);

        bytes32 idx = keccak256(
            abi.encode(validator, amount, msg.sender, block.number)
        );

        undelegations[idx] = UndelegationInfo(
            validator,
            payable(msg.sender),
            amount,
            block.number
        );
        allUndelegations.add(idx);

        // /// record delegate
        // bytes32 idxx = keccak256(
        //     abi.encode(block.number, validator, msg.sender, amount, uint256(2))
        // );

        // Record storage r = records[idxx];
        // r.height = block.number;
        // r.validator = validator;
        // r.delegator = msg.sender;
        // r.amount = amount;
        // r.ty = RecordType.Undelegate;

        // delegatorRecordIndex[msg.sender].push(idxx);

        emit Undelegation(validator, msg.sender, amount);
    }

    function adminUndelegate(
        address validator,
        address delegator,
        uint256 amount
    ) external override {
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator");

        require(amount > 0, "amount must be greater than 0");

        Delegator storage d = delegators[delegator];
        require(
            amount <= d.boundAmount[validator],
            "amount greater than bound amount"
        );

        _delDelegator(delegator, validator, amount);

        bytes32 idx = keccak256(
            abi.encode(validator, amount, delegator, block.number)
        );

        undelegations[idx] = UndelegationInfo(
            validator,
            payable(delegator),
            amount,
            block.number
        );
        allUndelegations.add(idx);

        emit Undelegation(validator, delegator, amount);
    }

    // Update validator
    // 该操作只能有 staker来操作
    function updateValidator(
        address validator,
        string calldata memo,
        uint256 rate
    ) public {
        // Check whether the validator is a stacker
        Validator storage v = validators[validator];
        require(v.staker == msg.sender, "only staker can do this operation");

        validators[validator].memo = memo;
        validators[validator].rate = rate;
    }

    // Return unDelegate assets
    function trigger() public override onlyRole(SYSTEM_ROLE) {
        uint256 blockNo = block.number;

        uint256 length = allUndelegations.length();

        for (uint256 i; i < length; i++) {
            bytes32 idx = allUndelegations.at(i);

            UndelegationInfo storage ur = undelegations[idx];

            // If this record reach target hright, send value and descrease amount.
            if ((blockNo - ur.height) >= unboundBlock) {
                _realDelDelegator(ur.delegator, ur.validator, ur.amount);

                // Send value
                address payable delegator = ur.delegator;
                delegator.sendValue(ur.amount);
            }
        }
    }

    function adminStake(
        address validator,
        bytes calldata public_key,
        address staker,
        string calldata memo,
        uint256 rate
    ) external payable override {
        // Check whether the validator was staked
        require(validators[validator].staker == address(0), "already staked");

        uint256 amount = dropAmount(msg.value, 12);

        require(amount * (10 ** 12) == msg.value, "lower 12 must be 0.");

        // require(amount >= stakeMininum, "amount too small");

        // uint256 maxDelegateAmount = maxDelegationAmountBasedOnTotalAmount();

        // require(amount <= maxDelegateAmount, "amount too large");

        PublicKeyType ty = PublicKeyType.Ed25519;

        Validator storage v = validators[validator];
        v.public_key = public_key;
        v.memo = memo;
        v.rate = rate;
        v.staker = staker;
        v.ty = ty;

        allValidators.add(validator);

        _addDelegator(staker, validator, amount);

        emit Stake(validator, public_key, ty, staker, msg.value, memo, rate);
    }

    // Delegate assets
    function adminDelegate(
        address validator,
        address delegator
    ) external payable {
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator");

        uint256 amount = dropAmount(msg.value, 12);

        require(amount * (10 ** 12) == msg.value, "lower 12 must be 0.");

        require(amount >= delegateMininum, "amount is too small");

        // uint256 maxDelegateAmount = maxDelegationAmountBasedOnTotalAmount();

        // require(amount <= maxDelegateAmount, "amount too large");

        _addDelegator(delegator, validator, amount);

        emit Delegation(validator, delegator, amount);
    }

    // -------- Function of power operation

    function powerDesc(
        address validator,
        address delegator,
        uint256 amount
    ) public onlyRole(POWER_ROLE) {
        uint256 bound = delegatorsBoundAmount(delegator, validator);

        uint256 realAmount;

        if (bound > amount) {
            realAmount = amount;
        } else {
            realAmount = bound;
        }
        delegators[delegator].boundAmount[validator] -= realAmount;
        delegators[delegator].amount -= realAmount;

        Validator storage v = validators[validator];
        v.power -= realAmount;

        totalDelegationAmount -= realAmount;
    }

    function systemSetDelegation(
        address validator,
        address delegator,
        uint256 amount
    ) public onlyRole(SYSTEM_ROLE) {
        _addDelegator(delegator, validator, amount);
    }

    function systemSetDelegationUnbound(
        address validator,
        address payable delegator,
        uint256 amount,
        uint256 target_height
    ) public onlyRole(SYSTEM_ROLE) {
        _delDelegator(delegator, validator, amount);

        bytes32 idx = keccak256(
            abi.encode(validator, amount, delegator, target_height)
        );

        undelegations[idx] = UndelegationInfo(
            validator,
            payable(delegator),
            amount,
            target_height
        );
        allUndelegations.add(idx);
    }

    // -------- utils function

    function dropAmount(
        uint256 amount,
        uint8 decimal
    ) public pure returns (uint256) {
        uint256 pow = 10 ** decimal;
        uint256 res = amount / pow;
        return res;
    }
}
