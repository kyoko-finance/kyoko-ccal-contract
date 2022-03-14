/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * trufflesuite.com/docs/advanced/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like @truffle/hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura accounts
 * are available for free at: infura.io/register.
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */

// const HDWalletProvider = require('@truffle/hdwallet-provider');
// const infuraKey = "fj4jll3k.....";
//
// const fs = require('fs');
// const mnemonic = fs.readFileSync(".secret").toString().trim();

const fs = require('fs');
const Web3 = require('web3')
const HDWalletProvider = require('@truffle/hdwallet-provider');
const infuraKey = fs.readFileSync(".infuraKey").toString().trim();
const mnemonic = fs.readFileSync(".mnemonic").toString().trim();
const alchemyKeyDev = fs.readFileSync(".alchemyKeyDev").toString().trim();
const etherscanApiKey = fs.readFileSync(".etherscanApi").toString().trim();
const polygonscanApiKey = fs.readFileSync(".polygonscanApi").toString().trim();
const bscscanApiKey = fs.readFileSync(".bscscanApi").toString().trim();

module.exports = {
    /**
     * Networks define how you connect to your ethereum client and let you set the
     * defaults web3 uses to send transactions. If you don't specify one truffle
     * will spin up a development blockchain for you on port 9545 when you
     * run `develop` or `test`. You can ask a truffle command to use a specific
     * network from the command line, e.g
     *
     * $ truffle test --network <network-name>
     */

    networks: {
        // Useful for testing. The `development` name is special - truffle uses it by default
        // if it's defined here and no other network is specified at the command line.
        // You should run a client (like ganache-cli, geth or parity) in a separate terminal
        // tab if you use this network and you must also set the `host`, `port` and `network_id`
        // options below to some value.
        //
        ganache: {
            host: "127.0.0.1", // Localhost (default: none)
            port: 7545, // Standard Ethereum port (default: none)
            network_id: "*", // Any network (default: none)
        },
        rinkeby: {
            provider: () => new HDWalletProvider(mnemonic, `https://rinkeby.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161`),
            network_id: 4,
            networkCheckTimeout: 1000000,
            confirmations: 2,    // # of confs to wait between deployments. (default: 0)
            timeoutBlocks: 20000,  // # of blocks before a deployment times out  (minimum/default: 50)
            skipDryRun: true,     // Skip dry run before migrations? (default: false for public nets )
        },
        kovan: {
            provider: () => new HDWalletProvider(mnemonic, `https://kovan.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161`),
            network_id: 42,
            networkCheckTimeout: 1000000,
            confirmations: 2,    // # of confs to wait between deployments. (default: 0)
            timeoutBlocks: 20000,  // # of blocks before a deployment times out  (minimum/default: 50)
            skipDryRun: true,     // Skip dry run before migrations? (default: false for public nets )
        },
        // bsc testnet
        bscTestnet: {
            provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-1-s1.binance.org:8545/`),
            network_id: 97,
            confirmations: 10,
            timeoutBlocks: 200,
            skipDryRun: true,
            networkCheckTimeout: 10000000,
        },
        // bsc
        bsc: {
            provider: () => new HDWalletProvider(mnemonic, `https://bsc-dataseed.binance.org/`),
            network_id: 56,
            confirmations: 10,
            timeoutBlocks: 200,
            skipDryRun: true
        },
        // ploygon Mumbai
        polygonTestnet: {
            provider: () => new HDWalletProvider(mnemonic, `https://polygon-mumbai.g.alchemy.com/v2/` + alchemyKeyDev),
            network_id: 80001,
            confirmations: 2,
            timeoutBlocks: 200,
            skipDryRun: true,
            networkCheckTimeout: 10000000,
        },
        // ploygon mainnet
        polygonMainnet: {
            provider: () => new HDWalletProvider(mnemonic, `https://polygon-mainnet.g.alchemy.com/v2/` + alchemyKeyDev),
            network_id: 137,
            confirmations: 10,
            timeoutBlocks: 200,
            skipDryRun: true,
            gasPrice: 33000000000
        },
        mainnet: {
            provider: () => new HDWalletProvider(mnemonic, `https://mainnet.infura.io/v3/` + infuraKey),
            network_id: 1,
            gasPrice: Web3.utils.toWei('150', 'gwei'),
            gas: 9999972
        },
        // Another network with more advanced options...
        // advanced: {
        // port: 8777,             // Custom port
        // network_id: 1342,       // Custom network
        // gas: 8500000,           // Gas sent with each transaction (default: ~6700000)
        // gasPrice: 20000000000,  // 20 gwei (in wei) (default: 100 gwei)
        // from: <address>,        // Account to send txs from (default: accounts[0])
        // websockets: true        // Enable EventEmitter interface for web3 (default: false)
        // },
        // Useful for deploying to a public network.
        // NB: It's important to wrap the provider as a function.
        // ropsten: {
        // provider: () => new HDWalletProvider(mnemonic, `https://ropsten.infura.io/v3/YOUR-PROJECT-ID`),
        // network_id: 3,       // Ropsten's id
        // gas: 5500000,        // Ropsten has a lower block limit than mainnet
        // confirmations: 2,    // # of confs to wait between deployments. (default: 0)
        // timeoutBlocks: 200,  // # of blocks before a deployment times out  (minimum/default: 50)
        // skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
        // },
        // Useful for private networks
        // private: {
        // provider: () => new HDWalletProvider(mnemonic, `https://network.io`),
        // network_id: 2111,   // This network is yours, in the cloud.
        // production: true    // Treats this network as if it was a public net. (default: false)
        // }
    },

    // Set default mocha options here, use special reporters etc.
    mocha: {
        // timeout: 100000
    },

    // Configure your compilers
    compilers: {
        solc: {
            version: "0.8.7", // Fetch exact version from solc-bin (default: truffle's version)
            // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
            settings: {
                // See the solidity docs for advice about optimization and evmVersion
                optimizer: {
                    enabled: true,
                    runs: 1,
                },
                // evmVersion: "byzantium",
            },
        },
    },
    plugins: [
        'truffle-contract-size',
        'truffle-plugin-verify'
    ],
    api_keys: {
        etherscan: etherscanApiKey,
        polygonscan: polygonscanApiKey,
        bscscan: bscscanApiKey
    }
};
