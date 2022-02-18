const fs = require('fs');
const ValidateLogic = artifacts.require('ValidateLogic');
const KyokoCCAL = artifacts.require("KyokoCCAL");

const util = require('../util');

const localEnvNetWork = 'ganache'.toUpperCase();
const MainChainNetWorkName = 'rinkeby'.toUpperCase();

module.exports = async function (deployer, network, accounts) {

    const [me] = accounts;

    const isLocalEnv = network.toUpperCase() === localEnvNetWork;
    const isMainChain = network.toUpperCase() === MainChainNetWorkName;
    const configStr = fs.readFileSync(`./deploy-${network}.json`, { encoding: 'utf-8' }, console.log);

    const config = JSON.parse(configStr);

    await deployer.deploy(ValidateLogic);

    await deployer.link(ValidateLogic, KyokoCCAL);

    await deployer.deploy(KyokoCCAL, config.CreditSystem, isLocalEnv || isMainChain, me);

    const ccal = await KyokoCCAL.deployed();

    const managerRol = await ccal.MANAGER_ROLE();

    await ccal.grantRole(managerRol, me);

    util({ KyokoCCAL: ccal.address }, `deploy-${network}.json`);

    console.log("Deploy KyokoCCAL success");
};
