const Errors = artifacts.require('Errors');
const ValidateLogic = artifacts.require('ValidateLogic');

const CCALMainChain = artifacts.require("CCALMainChain");

// const CreditSystem = artifacts.require("CreditSystem");
// const USDT = artifacts.require("USDT");

const util = require('../util');

const { deployProxy, upgradeProxy, prepareUpgrade } = require('@openzeppelin/truffle-upgrades');

const LZ_ENDPOINTS = require("../constants/layerzeroEndpoints.json");

module.exports = async function (deployer, network) {
    if (true) {
        await Errors.deployed();
        await deployer.link(Errors, CCALMainChain);
    } else {
        await deployer.deploy(Errors);
        await Errors.deployed();
        await deployer.link(Errors, CCALMainChain);
    }
    
    if (true) {
        await ValidateLogic.deployed();
        await deployer.link(ValidateLogic, CCALMainChain);
    } else {
        await deployer.deploy(ValidateLogic);
        await ValidateLogic.deployed();
        await deployer.link(ValidateLogic, CCALMainChain);
    }

    try {
        if (true) {
            const deployedConfig = require(`../deploy-${network}.json`);
            await prepareUpgrade(deployedConfig.CCALAddress, CCALMainChain, {deployer, unsafeAllow: ["external-library-linking"]});
            await upgradeProxy(deployedConfig.CCALAddress,
                CCALMainChain,
                {
                    deployer,
                    initializer: 'initialize',
                    // overwrite: true,
                    unsafeAllow: ["external-library-linking"]
                }
            );
        } else {
            // const CreditContract = await CreditSystem.deployed();
            // const USDTContract = await USDT.deployed();

            await deployProxy(CCALMainChain, [
                '_creditSystem',
                '_vault',
                500, // fee
                LZ_ENDPOINTS[network][0], // see https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
                LZ_ENDPOINTS[network][1], // see https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
                '_currency',
                18
            ],
            {
                deployer,
                initializer: 'initialize',
                // overwrite: true,
                unsafeAllow: ["external-library-linking"]
            });
        }

        console.table({ address: CCALMainChain.address });
        util({ CCALAddress: CCALMainChain.address }, `deploy-${network}.json`);
    } catch (e) {
        console.error(e);
    }
};
