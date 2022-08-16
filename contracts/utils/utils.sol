// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Utils {
    // Check amount
    function checkAmount(uint256 amount, uint8 decimal)
        public
        pure
        returns (uint256, uint256)
    {
        uint256 pow = 10**decimal;
        uint256 power = amount / pow;
        require(power * pow == amount, "amount error, low 12 must be 0.");
        return (amount, power);
    }
}
