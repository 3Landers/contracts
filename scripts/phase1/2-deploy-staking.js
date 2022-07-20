//to run this on testnet:
// $ npx hardhat run scripts/phase1/2-deploy-staking.js

const hardhat = require('hardhat')

async function deploy(name, ...params) {
  //deploy the contract
  const ContractFactory = await hardhat.ethers.getContractFactory(name);
  const contract = await ContractFactory.deploy(...params);
  await contract.deployed();

  return contract;
}

function getRole(name) {
  if (!name || name === 'DEFAULT_ADMIN_ROLE') {
    return '0x0000000000000000000000000000000000000000000000000000000000000000';
  }

  return '0x' + Buffer.from(
    hardhat.ethers.utils.solidityKeccak256(['string'], [name]).slice(2)
    , 'hex'
  ).toString('hex');
}

async function main() {
  //get network and admin
  const network = hardhat.config.networks[hardhat.config.defaultNetwork]
  const admin = new ethers.Wallet(network.accounts[0])
  const nft = { address: network.contracts.nft }
  const token = { address: network.contracts.token }

  console.log('Deploying ERC721Staking ...')
  const staking = await deploy(
    'ERC721Staking', 
    nft.address, 
    token.address, 
    admin.address
  )

  console.log('')
  console.log('-----------------------------------')
  console.log('ERC721Staking deployed to:', staking.address)
  console.log(
    'npx hardhat verify --show-stack-traces --network',
    hardhat.config.defaultNetwork,
    staking.address,
    `"${nft.address}"`,
    `"${token.address}"`,
    `"${admin.address}"`
  )
  console.log('')
  console.log('-----------------------------------')
  console.log('Roles:')
  console.log(' - ERC721Staking: STAKER_ROLE, CURATOR_ROLE')
  console.log('')
  console.log('-----------------------------------')
  console.log('Next Steps:')
  console.log('In ERC721Staking contract, grant STAKER_ROLE, CURATOR_ROLE to admin (choose another wallet)')
  console.log(` - ${network.scanner}/address/${staking.address}#writeContract`)
  console.log(` - grantRole( ${getRole('STAKER_ROLE')}, ${admin.address} )`)
  console.log(` - grantRole( ${getRole('CURATOR_ROLE')}, ${admin.address} )`)
  console.log('')
  console.log('In ERC20Soulbound contract, grant MINTER_ROLE to staking contract')
  console.log(` - ${network.scanner}/address/${token.address}#writeContract`)
  console.log(` - grantRole( ${getRole('MINTER_ROLE')}, ${staking.address} )`)
  console.log('')
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().then(() => process.exit(0)).catch(error => {
  console.error(error)
  process.exit(1)
});