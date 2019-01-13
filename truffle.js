require('dotenv').config()
var HDWalletProvider = require("truffle-hdwallet-provider");

var mnemonic = process.env["metamaskMnemonic"]

module.exports = {
  networks: {
    ganache: {
      host: "localhost",
      port: 7545,
      network_id: "*"
    },
    ropsten: {
     provider: () =>
       new HDWalletProvider(mnemonic, "https://ropsten.infura.io/v3/f565925a6c5143188b5589a37b28139b"),
     network_id: '3',
    },
   rinkeby: {
    provider: () =>
      new HDWalletProvider(mnemonic, "https://rinkeby.infura.io/v3/f565925a6c5143188b5589a37b28139b"),
    network_id: '4',
    }
  }
};
