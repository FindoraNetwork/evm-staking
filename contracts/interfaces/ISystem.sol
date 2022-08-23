// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IBase.sol";

interface ISystem is IBase {
    function getValidatorInfoList() external returns (ValidatorInfo[] memory);

    function blockTrigger(
        address proposer,
        address[] memory signed,
        uint256 circulationAmount,
        address[] memory byztine,
        ByztineBehavior[] memory behavior
    ) external;

    // 移到IBase.sol了
    //    struct ClaimOps {
    //        address addr;
    //        uint256 amount;
    //    }

    function getClaimOps() external returns (ClaimOps[] memory);
}
