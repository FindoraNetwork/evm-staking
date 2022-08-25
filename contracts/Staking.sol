// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Power.sol";
import "./utils/utils.sol";
import "./interfaces/IStaking.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Staking is Initializable, AccessControlEnumerable, IStaking, Utils {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM");
    bytes32 public constant REWARD_ROLE = keccak256("REWARD");

    uint256 public delegateTotal; // Total delegate amount
    address public system; // System contract address
    address public powerAddress; // Power contract address
    uint256 public stakeMinimum; // Minimum number of stacks
    uint256 public delegateMinimum; // Minimum number of delegate
    uint256 public powerProportionMaximum; // default 5
    uint256 public blockInterval; // Block out frequency
    uint256 public heightDifference; // number of blocks to wait,21days

    struct Validator {
        bytes public_key; // Validator public key
        string memo; //
        uint256 rate; // Length is 18
        address staker; // fra/0x
    }

    /*
     * address is tendermint-address
     * (validator address => Validator)
     */
    mapping(address => Validator) public validators;

    // Addresses of all validators
    EnumerableSet.AddressSet private allValidators;

    /*
     * All delegators of a validator
     * (validator address => delegator address set).
     */
    mapping(address => EnumerableSet.AddressSet) private delegatorsOfValidators;

    /*
     * Delegate info
     * (delegator => (validator => amount)).
     */
    mapping(address => mapping(address => uint256)) public delegators;
    // (delegator => total delegate amount).
    mapping(address => uint256) public delegateInfo;

    struct UnDelegationRecord {
        address validator;
        address payable receiver;
        uint256 amount;
        uint256 height;
    }

    // UnDelegation records
    UnDelegationRecord[] public unDelegationRecords;
    /*
     * 在21天等待期的记录
     * (undelegated address => mapping(validator address => amount))
     */
    mapping(address => mapping(address => uint256)) public unDelegatingRecords;

    event Stake(
        bytes public_key,
        address staker,
        uint256 amount,
        string memo,
        uint256 rate
    );
    event Delegation(address validator, address receiver, uint256 amount);
    event UnDelegation(address validator, address receiver, uint256 amount);

    function initialize(
        address system_,
        address powerAddress_,
        uint256 stakeMinimum_,
        uint256 delegateMinimum_,
        uint256 powerProportionMaximum_,
        uint256 blockInterval_
    ) public initializer {
        system = system_;
        powerAddress = powerAddress_;
        stakeMinimum = stakeMinimum_;
        delegateMinimum = delegateMinimum_;
        powerProportionMaximum = powerProportionMaximum_;
        blockInterval = blockInterval_;
        heightDifference = (86400 / blockInterval) * 21;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function adminSetSystemAddress(address system_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        system = system_;
    }

    function adminSetPowerAddress(address powerAddress_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        powerAddress = powerAddress_;
    }

    function adminSetStakeMinimum(uint256 stakeMinimum_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        stakeMinimum = stakeMinimum_;
    }

    function adminSetDelegateMinimum(uint256 delegateMinimum_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        delegateMinimum = delegateMinimum_;
    }

    function adminSetPowerProportionMaximum(uint256 powerProportionMaximum_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        powerProportionMaximum = powerProportionMaximum_;
    }

    function adminSetBlockInterval(uint256 blockInterval_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        blockInterval = blockInterval_;
        heightDifference = (86400 / blockInterval) * 21;
    }

    function _addDelegateAmountAndPower(
        address validator,
        address delegator,
        uint256 amount
    ) internal onlyRole(DEFAULT_ADMIN_ROLE) {
        delegators[delegator][validator] += amount;
        delegateInfo[delegator] += amount;
        delegateTotal += amount;

        uint256 power = amount;
        Power powerContract = Power(powerAddress);
        powerContract.addPower(validator, power);
    }

    function _descDelegateAmountAndPower(
        address validator,
        address delegator,
        uint256 amount
    ) internal onlyRole(DEFAULT_ADMIN_ROLE) {
        delegators[delegator][validator] -= amount;
        delegateInfo[delegator] -= amount;
        delegateTotal -= amount;

        uint256 power = amount;
        Power powerContract = Power(powerAddress);
        powerContract.descPower(validator, power);
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

        // Stake amount
        require(msg.value >= stakeMinimum, "amount too less");
        uint256 amount;
        uint256 power;
        (amount, power) = convertAmount(msg.value, 12);

        Validator storage v = validators[validator];
        v.public_key = public_key;
        v.memo = memo;
        v.rate = rate;
        v.staker = msg.sender;

        _addDelegateAmountAndPower(validator, msg.sender, amount);

        allValidators.add(validator);

        emit Stake(public_key, msg.sender, msg.value, memo, rate);
    }

    // Delegate assets
    function delegate(address validator) external payable override {
        // Check whether the validator is a stacker
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator");

        // Check delegate amount
        require(msg.value >= delegateMinimum, "amount is too less");
        uint256 amount;
        uint256 power;
        (amount, power) = convertAmount(msg.value, 12);

        Power powerContract = Power(powerAddress);
        require(
            power <
                (powerContract.powerTotal() + power) / powerProportionMaximum,
            "amount is too large"
        );

        _addDelegateAmountAndPower(validator, msg.sender, amount);

        delegatorsOfValidators[validator].add(msg.sender);

        emit Delegation(validator, address(this), amount);
    }

    // UnDelegate assets
    function undelegate(address validator, uint256 amount) external override {
        // Check whether the validator is a stacker
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator");

        // Check unDelegate amount
        require(amount > 0, "amount must be greater than 0");
        convertAmount(amount, 12);
        // Get mount of 21 day waiting period
        uint256 waitingAmount = unDelegatingRecords[msg.sender][validator];
        require(
            delegators[msg.sender][validator] >= amount + waitingAmount,
            "amount is too large"
        );

        // Update record of 21 day waiting period
        unDelegatingRecords[msg.sender][validator] += amount;

        // Push record
        unDelegationRecords.push(
            UnDelegationRecord(
                validator,
                payable(msg.sender),
                amount,
                block.number
            )
        );
    }

    // Return unDelegate assets
    function trigger() public onlyRole(SYSTEM_ROLE) {
        uint256 blockNo = block.number;
        Power powerContract = Power(powerAddress);
        for (uint256 i; i < unDelegationRecords.length; i++) {
            if ((blockNo - unDelegationRecords[i].height) >= heightDifference) {
                Address.sendValue(
                    unDelegationRecords[i].receiver,
                    unDelegationRecords[i].amount
                );

                // Decrease amount and power
                // 减去质押amount，减去power，在undelegate时候已经判断过金额，这里不必判断会减为负数,以及后12位

                // Update delegate amount and decrease power of validator
                _descDelegateAmountAndPower(
                    unDelegationRecords[i].validator,
                    unDelegationRecords[i].receiver,
                    unDelegationRecords[i].amount
                );

                // Update the amount of 21 day waiting period
                unDelegatingRecords[unDelegationRecords[i].receiver][
                    unDelegationRecords[i].validator
                ] -= unDelegationRecords[i].amount;

                // Remove the delegator of validator, if the delegate amount is 0
                // 当某一质押者在某节点质押金额变为0，就从该节点下质押者地址集合移除质押者账户地址
                if (
                    delegators[unDelegationRecords[i].receiver][
                        unDelegationRecords[i].validator
                    ] == 0
                ) {
                    delegatorsOfValidators[unDelegationRecords[i].validator]
                        .remove(unDelegationRecords[i].receiver);
                }

                // Removed from the validator set If the power of validator was reduced to 0
                if (
                    powerContract.getPower(unDelegationRecords[i].validator) ==
                    0
                ) {
                    allValidators.remove(unDelegationRecords[i].validator);
                }

                // Event
                emit UnDelegation(
                    unDelegationRecords[i].validator,
                    unDelegationRecords[i].receiver,
                    unDelegationRecords[i].amount
                );
            }
        }
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
        require(
            (v.staker != address(0)) && (v.staker == msg.sender),
            "invalid staker"
        );

        validators[validator].memo = memo;
        validators[validator].rate = rate;
    }

    // Get all validator's addresses
    function getAllValidators() public view returns (address[] memory) {
        return allValidators.values();
    }

    // Get all delegators of a validator
    function getDelegatorsByValidator(address validator)
        public
        view
        returns (address[] memory)
    {
        return delegatorsOfValidators[validator].values();
    }

    // Get staker address of a validator
    function getStakerByValidator(address validator)
        public
        view
        returns (address)
    {
        return validators[validator].staker;
    }

    // Check whether an validator-account is a Legal validator
    function isValidator(address validator) public view returns (bool) {
        return allValidators.contains(validator);
    }

    // Get delegate amount
    function getDelegateAmount(address validator, address delegator)
        public
        view
        returns (uint256)
    {
        return delegators[validator][delegator];
    }

    // Get staker delegate amount
    function getStakerDelegateAmount(address validator)
        public
        view
        returns (uint256)
    {
        return delegators[validator][validators[validator].staker];
    }

    // Get validator rate
    function getValidatorRate(address validator) public view returns (uint256) {
        return validators[validator].rate;
    }

    // Get total delegate amount of a delegator
    function getDelegateTotalAmount(address delegator)
        public
        view
        onlyRole(REWARD_ROLE)
        returns (uint256)
    {
        return delegateInfo[delegator];
    }

    // Check the last 12 digits of the amount before use
    function descDelegateAmountAndPower(
        address validator,
        address delegator,
        uint256 amount
    ) public onlyRole(SYSTEM_ROLE) {
        require(
            delegators[delegator][validator] >= amount,
            "insufficient amount"
        );

        // Update delegator's delegate-amount of validator
        delegators[delegator][validator] -= amount;
        // Decrease total delegate-amount of delegator
        delegateInfo[delegator] -= amount;
        // Decrease total delegate-amount
        delegateTotal -= amount;

        // Decrease power
        uint256 power = amount;
        Power powerContract = Power(powerAddress);
        powerContract.descPower(validator, power);
    }
}
