// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IStaking {
    function stake(
        address validator,
        bytes calldata public_key,
        string calldata memo,
        uint256 rate
    ) external payable;

    function delegate(address validator) external payable;

    function undelegate(address validator, uint256 amount) external;

    function updateValidator(
        address validator,
        string calldata memo,
        uint256 rate
    ) external;

    function trigger() external;

    function systemStake(
        address validator,
        bytes calldata public_key,
        address staker,
        bytes calldata staker_pk,
        string calldata memo,
        uint256 rate
    ) external payable;

    function systemDelegate(
        address validator,
        address delegator,
        bytes calldata delegator_pk
    ) external payable;

    function systemUndelegate(
        address validator,
        address delegator,
        uint256 amount
    ) external;

    function systemUpdateValidator(
        address validator,
        string calldata memo,
        uint256 rate
    ) external;
}
