// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBase {
    struct ValidatorInfo {
        bytes public_key;
        address addr;
        uint256 power;
    }

    enum ByztineBehavior {
        DuplicateVote,
        LightClientAttack,
        Unknown
    }

    struct ClaimOps {
        address addr;
        uint256 amount;
    }
}
