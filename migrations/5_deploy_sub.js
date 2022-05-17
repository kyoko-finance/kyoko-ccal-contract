const ValidateLogic = artifacts.require('ValidateLogic');
const CCALSubChain = artifacts.require("CCALSubChain");
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

module.exports = async function (deployer) {
    try {
        await deployer.deploy(ValidateLogic);
    
        await deployer.link(ValidateLogic, CCALSubChain);

    } catch (error) {
        console.log('lib e: ', error);
        process.exit(1);
    }
    try {
        await deployProxy(CCALSubChain, [
            '0x6Fcb97553D41516Cb228ac03FdC8B9a0a9df04A1',
            10002,
            10001
        ],
            {
                deployer,
                initializer: 'initialize',
                overwrite: true,
                unsafeAllow: ["external-library-linking"]
        });

        console.table({ address: CCALSubChain.address });
    } catch (error) {
        console.log('e: ', JSON.stringify(error));
    }
};
