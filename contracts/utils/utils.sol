// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Utils {
    // Check decimal
    function checkDecimal(uint256 amount, uint8 decimal)
        public
        pure
        returns (uint256)
    {
        uint256 pow = 10**decimal;
        uint256 a = amount / pow;

        return a * pow;
    }
}
