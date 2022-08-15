// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./utils/utils.sol";
import "./Power.sol";
import "./interfaces/IStaking.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Staking is Initializable, OwnableUpgradeable, IStaking, Utils {
    using Address for address;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    address public system; // System contract address
    address public powerAddress; // Power contract address
    uint256 public stakeMinimum;
    uint256 public delegateMinimum;
    uint256 public blockInterval; //

    struct Validator {
        bytes public_key;
        //        uint256 power;
        string memo;
        uint256 rate;
        address staker;
    }
    // (validator address => Validator)
    mapping(address => Validator) public validators;

    EnumerableMap.UintToAddressMap private myMap;

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

    function initialize(
        address system_,
        address powerAddress_,
        uint256 stakeMinimum_,
        uint256 delegateMinimum_,
        uint256 blockInterval_
    ) public initializer {
        system = system_;
        powerAddress = powerAddress_;
        stakeMinimum = stakeMinimum_;
        delegateMinimum = delegateMinimum_;
        blockInterval = blockInterval_;
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    modifier onlySystem() {
        require(msg.sender == system, "only called by system");
        _;
    }

    function SetConfig(address system_, address powerAddress_)
        public
        onlyOwner
    {
        system = system_;
        powerAddress = powerAddress_;
    }

    // Stake
    function stake(
        address validator,
        bytes calldata public_key,
        string calldata memo,
        uint256 rate
    ) external payable override {
        // Stake amount
        require(msg.value >= stakeMinimum, "amount too less");
        uint256 amount = checkDecimal(msg.value, 12);
        require(msg.value == amount, "amount error, low 12 must be 0.");
        uint256 power = amount / (10**12);

        Validator storage v = validators[validator];
        v.public_key = public_key;
        v.memo = memo;
        v.rate = rate;
        v.staker = msg.sender;
        //        v.power = msg.value;
        Power powerContract = Power(powerAddress);
        powerContract.addPower(validator, power);

        emit Stake(validator, msg.sender, msg.value);
    }

    // Delegate assets
    function delegate(address validator) external payable override {
        // Check whether the validator is a stacker
        Validator storage v = validators[validator];
        require(v.staker != address(0), "invalid validator");

        // Check delegate amount
        require(msg.value >= delegateMinimum, "amount is too less");
        uint256 amount = checkDecimal(msg.value, 12);
        require(msg.value == amount, "amount error, low 12 must be 0.");
        Power powerContract = Power(powerAddress);
        uint256 power = amount / (10**12);
        require(power < powerContract.powerTotal() / 5, "amount is too large");

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
        uint256 amountDeci = checkDecimal(amount, 12);
        require(amountDeci == amount, "amount error, low 12 must be 0.");
        require(
            delegators[msg.sender][validator] >= amount,
            "amount is too large"
        );

        Power powerContract = Power(powerAddress);
        uint256 power = amount / (10**12);
        delegators[msg.sender][validator] -= amount;
        powerContract.descPower(validator, power);

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
    function trigger() public onlySystem {
        uint256 blockNo = block.number;
        // 86400/15*21，blockInterval
        uint256 heightDifference = (86400 / blockInterval) * 21;
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
}
