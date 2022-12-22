require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('hardhat-abi-exporter');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: "0.8.9",
    networks: {
        hardhat: {},
        localhost: {
            url: "http://localhost:8545",
            accounts: ["0x4d05b965f821ea900ddd995dfa1b6caa834eaaa1ebe100a9760baf9331aae567"]
        },
        qa02: {
            url: "https://dev-qa02.dev.findora.org:8545",
            accounts: ["0x4d05b965f821ea900ddd995dfa1b6caa834eaaa1ebe100a9760baf9331aae567"]
        },
        qa04: {
            url: "https://dev-qa04.dev.findora.org:8545",
            accounts: ["0x4d05b965f821ea900ddd995dfa1b6caa834eaaa1ebe100a9760baf9331aae567"]
        }
    },
    abiExporter: {
        path: './data/abi',
        runOnCompile: true,
        clear: true,
        flat: true,
        spacing: 2,
        pretty: false,
        format: "json"
    }
};
