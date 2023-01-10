// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers } = require("hardhat");
const axios = require("axios");
const utils = require("./address_utils");

async function main() {
    let memo1 = {"desc":"a","logo":"https://i.imgur.com/JfxwM7J.png","name":"Koncrete Validator","website":"Koncrete.org"};

    const sa = "0x72488bAa718F52B76118C79168E55c209056A2E6";

    let validatos = await axios.get("http://localhost:26657/validators");

    let vs = validatos.data.result.validators;

    const Staking = await ethers.getContractFactory("Staking");

    const addrs = await utils.get_address();

    const staking = await Staking.attach(addrs.staking);

    for (let v of vs) {
        let address = '0x' + v.address;
        let public_key = '0x' + Buffer.from(v.pub_key.value, 'base64').toString('hex');

        console.log("stake to:", address)
        console.log("public key is:", public_key);

        await staking.adminStake(address, public_key, sa, JSON.stringify(memo1), 20000, {
            value: ethers.utils.parseEther("3000000"),
        });

        console.log();
    }

    await staking.adminUnboundBlock(4);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
