//to run this on testnet:
// $ npx hardhat run scripts/phase1/0-deploy-mock.js

const hardhat = require('hardhat')

async function deploy(name, ...params) {
  //deploy the contract
  const ContractFactory = await hardhat.ethers.getContractFactory(name);
  const contract = await ContractFactory.deploy(...params);
  await contract.deployed();

  return contract;
}

async function main() {
  console.log('Deploying ERC721Mock ...')
  const nft = await deploy('ERC721Mock')

  console.log('')
  console.log('-----------------------------------')
  console.log('ERC721Mock deployed to:', nft.address)
  console.log(
    'npx hardhat verify --show-stack-traces --network',
    hardhat.config.defaultNetwork,
    nft.address
  )
  console.log('')
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().then(() => process.exit(0)).catch(error => {
  console.error(error)
  process.exit(1)
});