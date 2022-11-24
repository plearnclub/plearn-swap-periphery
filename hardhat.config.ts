import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@openzeppelin/hardhat-upgrades";

import { mnemonic, bscScanApiKey, etherScanApiKey, polygonscanApiKey } from "./secrets.json";

export default {
  defaultNetwork: "hardhat",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {
      blockGasLimit: 99999999
    },
    mainnet: {
      url: "https://mainnet.infura.io/v3/",
      chainId: 1,
      accounts: { mnemonic: mnemonic }
    },
    rinkeby: {
      url: "https://rinkeby.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161",
      chainId: 4,
      accounts: { mnemonic: mnemonic },
      blockGasLimit: 99999999
    },
    goerli: {
      url: "https://goerli.infura.io/v3/",
      chainId: 5,
      accounts: { mnemonic: mnemonic },
      blockGasLimit: 99999999
    },
    sepolia: {
      url: "https://sepolia.infura.io/v3/",
      chainId: 11155111,
      accounts: { mnemonic: mnemonic },
      blockGasLimit: 99999999
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts: { mnemonic: mnemonic },
    },
    bscTestnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts: { mnemonic: mnemonic },
      blockGasLimit: 99999999
    },
    polygon: {
      url: "https://polygon-rpc.com/",
      chainId: 137,
      accounts: { mnemonic: mnemonic }
    },
    polygonMumbai: {
      url: "https://matic-mumbai.chainstacklabs.com",
      chainId: 80001,
      accounts: { mnemonic: mnemonic },
      blockGasLimit: 99999999
    }
  },
  etherscan: {
    apiKey: {
      mainnet: etherScanApiKey,
      rinkeby: etherScanApiKey,
      goerli: etherScanApiKey,
      sepolia: etherScanApiKey,
      bsc: bscScanApiKey,
      bscTestnet: bscScanApiKey,
      polygon: polygonscanApiKey,
      polygonMumbai: polygonscanApiKey
    }
  },
  solidity: {
    compilers: [{
      version: "0.8.4",
      settings: {
        optimizer: {
          enabled: true,
          runs: 1000
        }
      }
    }
    ]
  }
};