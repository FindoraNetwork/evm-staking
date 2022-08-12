// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./utils/utils.sol";
import "./interfaces/IStaking.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Staking is Ownable, IStaking, Utils {
    using Address for address;

    address public system;
    uint256 public stakeMinimum;
    uint256 public powerTotal;

    struct Validator {
        bytes public_key;
        uint256 power;
        string memo;
        uint256 rate;
        address staker;
    }

    // (validator address => Validator)
    mapping(address => Validator) public validators;

    // Enumable.

    // (delegator => (validator => amount)).
    mapping(address => mapping(address => uint256)) public delegators;

    struct UnDelegationRecord {
        address staker;
        address payable receiver;
        uint256 amount;
        uint256 height;
    }

    UnDelegationRecord[] public unDelegationRecords;

    event Stake(address validator, address staker, uint256 amount);
    event Delegation(address validator, address receiver, uint256 amount);
    event UnDelegation(address validator, address receiver, uint256 amount);

    constructor(address system_, uint256 stakeMinimum_) {
        system = system_;
        stakeMinimum = stakeMinimum_;
    }

    modifier onlySystem() {
        require(msg.sender == system, "only called by system");
        _;
    }

    // Stake
    function stake(
        address validator,
        bytes calldata public_key,
        string calldata memo,
        uint256 rate
    ) external payable override {
        require(msg.value >= stakeMinimum, "stake too less");

        Validator storage v = validators[validator];
        v.public_key = public_key;
        v.memo = memo;
        v.rate = rate;
        v.staker = msg.sender;
        v.power = msg.value;

        emit Stake(validator, msg.sender, msg.value);
    }

    // Delegate assets
    function delegate(address validator) external payable override {
        // Check whether the validator is a stacker
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator"); // The validator is not a stacker

        // Check delegate amount
        require(msg.value>0, "amount must be greater than 0");
        uint256 amount = checkDecimal(msg.value, 12);
        require(msg.value == amount, "low 12 must be 0.");
        uint256 power = amount / (10**12);
        require(power < powerTotal / 5, "the amount is too large");

        delegators[msg.sender][validator] += amount;
        validators[validator].power += power;
        powerTotal += power;

        emit Delegation(validator, address(this), amount);
    }

    // UnDelegate assets
    function undelegate(address validator, uint256 amount) external override {
        // Check whether the validator is a stacker
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator"); // The validator is not a stacker

        // Check undelegate amount
        require(amount>0, "amount must be greater than 0");
        uint256 amountDeci = checkDecimal(amount, 12);
        require(amountDeci == amount, "amount error, low 12 must be 0.");
        require(
            delegators[msg.sender][validator] >= amount,
            "the amount is too large"
        );

        uint256 power = amount / (10**12);
        delegators[msg.sender][validator] -= amount;
        validators[validator].power -= power;
        powerTotal -= power;

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

    // Trigger return assets event
    function trigger() public onlySystem {
        uint256 blockNo = block.number;
        uint256 heightDifference = 120960;
        // 86400/15*21
        for (uint256 i; i < unDelegationRecords.length; i++) {
            if ((blockNo - heightDifference) >= unDelegationRecords[i].height) {
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
}
