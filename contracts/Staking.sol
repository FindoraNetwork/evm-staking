// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Power.sol";
import "./utils/utils.sol";
import "./interfaces/IStaking.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Staking is Initializable, AccessControlEnumerable, IStaking, Utils {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM");

    address public system; // System contract address
    address public powerAddress; // Power contract address
    uint256 public stakeMinimum;
    uint256 public delegateMinimum;
    uint256 public powerProportionMaximum; // default 5
    uint256 public blockInterval; //
    uint256 public heightDifference; // number of blocks to wait,21days

    struct Validator {
        bytes public_key;
        string memo;
        uint256 rate; // length is 18
        address staker; // fra/0x
    }
    /*
     * address（tendermint address）
     * (validator address => Validator)
     */
    mapping(address => Validator) public validators;

    EnumerableSet.AddressSet private allValidators;

    // (delegator => (validator => amount)).
    mapping(address => mapping(address => uint256)) public delegators;

    struct UnDelegationRecord {
        address staker;
        address payable receiver;
        uint256 amount;
        uint256 height;
    }

    UnDelegationRecord[] public unDelegationRecords;

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
        Power powerContract = Power(powerAddress);
        powerContract.addPower(validator, power);

        delegators[msg.sender][msg.sender] += amount;

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

        delegators[msg.sender][validator] += amount;

        powerContract.addPower(validator, power);

        emit Delegation(validator, address(this), amount);
    }

    // UnDelegate assets
    function undelegate(address validator, uint256 amount) external override {
        // Check whether the validator is a stacker
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator");

        // Check unDelegate amount
        require(amount > 0, "amount must be greater than 0");
        uint256 power;
        (, power) = convertAmount(amount, 12);
        require(
            delegators[msg.sender][validator] >= amount,
            "amount is too large"
        );

        delegators[msg.sender][validator] -= amount;

        Power powerContract = Power(powerAddress);
        powerContract.descPower(validator, power);

        if (powerContract.getPower(validator) == 0) {
            allValidators.remove(validator);
            delete validators[validator];
        }

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
        for (uint256 i; i < unDelegationRecords.length; i++) {
            if ((blockNo - unDelegationRecords[i].height) >= heightDifference) {
                Address.sendValue(
                    unDelegationRecords[i].receiver,
                    unDelegationRecords[i].amount
                );

                emit UnDelegation(
                    unDelegationRecords[i].staker,
                    unDelegationRecords[i].receiver,
                    unDelegationRecords[i].amount
                );
            }
        }
    }

    // Update staker
    function updateStaker(
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

    function getAllValidators() public view returns (address[] memory) {
        return allValidators.values();
    }

    function hasValidators(address validator) public view returns (bool) {
        return allValidators.contains(validator);
    }
}
