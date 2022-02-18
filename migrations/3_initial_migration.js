const USDT = artifacts.require("USDT");

const util = require('../util');

module.exports = async function (deployer, network) {

    await deployer.deploy(USDT, "Tether USD", "USDT");

    const usdt = await USDT.deployed();

    util({ USDT: usdt.address }, `deploy-${network}.json`);

    console.log("USDT deploy success");
};
