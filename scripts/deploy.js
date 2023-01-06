// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat");
const utils = require("./address_utils");

async function redeploySystem(proxy_addr) {
    const System = await ethers.getContractFactory("System");
    const system = await System.deploy(proxy_addr);
    await system.deployed();

    const P = await ethers.getContractFactory("SystemProxy");
    const proxy = await P.attach(proxy_addr);
    await proxy.adminSetSystemAddress(system.address);

    console.log("System address:", system.address);

    return system.address;
}

async function deployAddressMapping() {
    const AddressMapping = await ethers.getContractFactory("AddressMapping");
    const addressMapping = await upgrades.deployProxy(AddressMapping, []);

    await addressMapping.deployed();

    console.log("AddressMapping address:", addressMapping.address);
    return addressMapping.address
}

async function deployStaking(system, addressMapping, prism) {
    const Staking = await ethers.getContractFactory("Staking");

    const staking = await upgrades.deployProxy(Staking, [system, addressMapping, prism]);

    await staking.deployed();

    console.log("Staking address:", staking.address);

    return staking.address;
}

async function deployPower(staking, min, max) {
    const Power = await ethers.getContractFactory("Power");

    const p = await Power.deploy(staking, min, max);

    await p.deployed();

    console.log("Power address:", p.address);

    return p.address;
}

async function deployReward(staking, system) {
    const Reward = await ethers.getContractFactory("Reward");
    const reward = await upgrades.deployProxy(Reward, [staking, system]);

    await reward.deployed();

    console.log("Reward address:", reward.address);

    return reward.address;
}

async function main() {
    const proxy = await utils.get_proxy_address();

    console.log("Proxy address:", proxy);

    const system_addr = await redeploySystem(proxy);

    const System = await ethers.getContractFactory("System");

    const system = await System.attach(system_addr);

    const address_mapping_addr = await deployAddressMapping();

    const staking_addr = await deployStaking(system_addr, address_mapping_addr, "0x5f9552fEd754F20B636C996DaDB32806554Bb995");
    await system.adminSetStakingAddress(staking_addr);

    const AddressMapping = await ethers.getContractFactory("AddressMapping");
    const address_mapping = AddressMapping.attach(address_mapping_addr);

    await address_mapping.adminSetStakingAddress(staking_addr);

    const power_addr = await deployPower(staking_addr, 5, 40);
    await system.adminSetPowerAddress(power_addr);

    const reward_addr = await deployReward(staking_addr, system_addr);
    await system.adminSetRewardAddress(reward_addr);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
