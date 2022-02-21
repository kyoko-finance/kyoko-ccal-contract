const fs = require('fs');
const ValidateLogic = artifacts.require('ValidateLogic');
const KyokoCCAL = artifacts.require("KyokoCCAL");
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const util = require('../util');

const localEnvNetWork = 'ganache'.toUpperCase();
const MainChainNetWorkName = 'rinkeby'.toUpperCase();

module.exports = async function (deployer, network) {
    try {
            
        const isLocalEnv = network.toUpperCase() === localEnvNetWork;
        const isMainChain = network.toUpperCase() === MainChainNetWorkName;
        const configStr = fs.readFileSync(`./deploy-${network}.json`, { encoding: 'utf-8' }, console.log);
    
        const config = JSON.parse(configStr);
        
        try {
            await deployer.deploy(ValidateLogic);
        
            await deployer.link(ValidateLogic, KyokoCCAL);
            
        } catch (error) {
            console.log('lib e: ', error);
        }
    
        await deployProxy(KyokoCCAL, [
            config.CreditSystem,
            isLocalEnv || isMainChain,
            '0x75a7767840cBE48DAF656E28F0Fd5bcfd151aa26',
            5
        ],
            {
                deployer,
                initializer: 'initialize',
                overwrite: true,
                unsafeAllow: ["external-library-linking"]
        });
    
        // const ccal = await KyokoCCAL.deployed();
    
        // await deployer.deploy(KyokoCCAL, config.CreditSystem, isLocalEnv || isMainChain, me);
    
        // const ccal = await KyokoCCAL.deployed();
    
        // const managerRol = await ccal.MANAGER_ROLE();
    
        // await ccal.grantRole(managerRol, me);
    
        util({ KyokoCCAL: KyokoCCAL.address }, `deploy-${network}.json`);
    
        console.log("Deploy KyokoCCAL success", KyokoCCAL.address);
    } catch (error) {
        console.log('e: ', JSON.stringify(error));
    }
};
