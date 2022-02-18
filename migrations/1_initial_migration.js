const CreditSystem = artifacts.require("CreditSystem");

const util = require('../util');

module.exports = async function (deployer, network) {

    await deployer.deploy(CreditSystem);

    const credit = await CreditSystem.deployed();

    util({ CreditSystem: credit.address }, `deploy-${network}.json`);

    console.log('deploy CreditSystem success');
};
