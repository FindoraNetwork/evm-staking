// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IByztine {
    enum ByztineBehavior {
        DuplicateVote,
        LightClientAttack,
        Unknown
    }
}
