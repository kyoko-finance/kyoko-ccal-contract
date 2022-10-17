const Errors = artifacts.require('Errors');
const ValidateLogic = artifacts.require('ValidateLogic');

const CCALSubChain = artifacts.require("CCALSubChain");
const { deployProxy, upgradeProxy, prepareUpgrade } = require('@openzeppelin/truffle-upgrades');

const util = require('../util');

const LZ_ENDPOINTS = require("../constants/layerzeroEndpoints.json");

module.exports = async function (deployer, network) {
    if (true) {
        await Errors.deployed();
        await deployer.link(Errors, CCALSubChain);
    } else {
        await deployer.deploy(Errors);
        await Errors.deployed();
        await deployer.link(Errors, CCALSubChain);
    }

    if (true) {
        await ValidateLogic.deployed();
        await deployer.link(ValidateLogic, CCALSubChain);
    } else {
        await deployer.deploy(ValidateLogic);
        await ValidateLogic.deployed();
        await deployer.link(ValidateLogic, CCALSubChain);
    }

    try {
        if (true) {
            const deployedConfig = require(`../deploy-${network}.json`);
            await prepareUpgrade(deployedConfig.CCALAddress, CCALSubChain, {deployer, unsafeAllow: ["external-library-linking"]});
            await upgradeProxy(deployedConfig.CCALAddress,
                CCALSubChain,
                {
                    deployer,
                    initializer: 'initialize',
                    // overwrite: true,
                    unsafeAllow: ["external-library-linking"]
                }
            );
        } else {
            await deployProxy(CCALSubChain, [
                LZ_ENDPOINTS[network][1],
                LZ_ENDPOINTS[network][0],
                LZ_ENDPOINTS[process.env.MAIN_CHAIN][0],
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

        console.table({ address: CCALSubChain.address });
        util({ CCALAddress: CCALSubChain.address }, `deploy-${network}.json`);
    } catch (e) {
        console.error(e);
    }
};
