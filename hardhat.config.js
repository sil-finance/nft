require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");
require('dotenv').config()

task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    bsc: {
      url: process.env.RPC_URL_BSC,
      accounts: [process.env.PK_ACCOUNT_1],
      timeout: 600000
    }
  },
  solidity: "0.8.0",
};

