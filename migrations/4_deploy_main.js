const ValidateLogic = artifacts.require('ValidateLogic');
const CCALMainChain = artifacts.require("CCALMainChain");
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

module.exports = async function (deployer) {
    try {
        await deployer.deploy(ValidateLogic);
    
        await deployer.link(ValidateLogic, CCALMainChain);

    } catch (error) {
        console.log('lib e: ', error);
        process.exit(1);
    }
    try {
        await deployProxy(CCALMainChain, [
            '[credit-system address]',
            '[vault address]',
            500, // fee
            10001, // see https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
            '0x79a63d6d8BBD5c6dfc774dA79bCcD948EAcb53FA', // see https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
            '[currency address]',
            '[currency decimal]'
        ],
            {
                deployer,
                initializer: 'initialize',
                overwrite: true,
                unsafeAllow: ["external-library-linking"]
        });

        console.table({ address: CCALMainChain.address });
    } catch (error) {
        console.log('e: ', JSON.stringify(error));
    }
};
