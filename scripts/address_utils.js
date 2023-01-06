const axios = require("axios");

async function get_proxy_address() {
    let checkpoint = await axios.get("http://localhost:8668/display_checkpoint");
    let proxy_address = checkpoint.data.evm_staking_address;

    return proxy_address;
}

async function get_system_address(proxy) {
    const P = await ethers.getContractFactory("SystemProxy");
    const p = await P.attach(proxy);

    return await p.systemAddress();
}

async function get_address_from_system(system_addr) {
    const System = await ethers.getContractFactory("System");

    const system = await System.attach(system_addr);

    const staking = await system.stakingAddress();
    const reward = await system.rewardAddress();
    const power = await system.powerAddress();

    return {
        staking,
        reward,
        power,
    }
}

async function get_address() {
    let proxy = await get_proxy_address();
    let system = await get_system_address(proxy);
    let { staking, reward, power } = await get_address_from_system(system);

    return {
        proxy,
        system,
        staking,
        reward,
        power
    }
}

module.exports = {
    get_proxy_address,
    get_address,
}

