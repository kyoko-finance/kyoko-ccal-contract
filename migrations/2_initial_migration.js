const Game = artifacts.require("Game");

const util = require('../util');

module.exports = async function (deployer, network) {

    await deployer.deploy(Game, "Game", "game");

    const game = await Game.deployed();

    util({ Game: game.address }, `deploy-${network}.json`);

    console.log('Game deploy success');
};
