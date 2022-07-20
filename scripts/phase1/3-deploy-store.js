//to run this on testnet:
// $ npx hardhat run scripts/phase1/3-deploy-store.js

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

const contract_uri = 'https://raw.githubusercontent.com/3Landers/contracts/main/data/store.json'
const base_uri = 'https://raw.githubusercontent.com/3Landers/contracts/main/data/samples/'

async function main() {
  //get network and admin
  const network = hardhat.config.networks[hardhat.config.defaultNetwork]
  const admin = new ethers.Wallet(network.accounts[0])
  const token = { address: network.contracts.token }

  console.log('Deploying ERC1155Store ...')
  const store = await deploy(
    'ERC1155Store', 
    contract_uri, 
    base_uri,
    token.address, 
    admin.address
  )

  console.log('')
  console.log('-----------------------------------')
  console.log('ERC1155Store deployed to:', store.address)
  console.log(
    'npx hardhat verify --show-stack-traces --network',
    hardhat.config.defaultNetwork,
    store.address,
    `"${contract_uri}"`,
    `"${base_uri}"`,
    `"${token.address}"`,
    `"${admin.address}"`
  )
  console.log('')
  console.log('-----------------------------------')
  console.log('Roles:')
  console.log(' - ERC1155Store: FUNDER_ROLE, MINTER_ROLE, PAUSER_ROLE, CURATOR_ROLE')
  console.log('')
  console.log('-----------------------------------')
  console.log('Next Steps:')
  console.log('In ERC1155Store contract, grant FUNDER_ROLE, MINTER_ROLE, CURATOR_ROLE to admin (choose another wallet)')
  console.log(` - ${network.scanner}/address/${store.address}#writeContract`)
  console.log(` - grantRole( ${getRole('FUNDER_ROLE')}, ${admin.address} )`)
  console.log(` - grantRole( ${getRole('MINTER_ROLE')}, ${admin.address} )`)
  console.log(` - grantRole( ${getRole('CURATOR_ROLE')}, ${admin.address} )`)
  console.log('')
  console.log('In ERC20Soulbound contract, grant BURNER_ROLE to store contract')
  console.log(` - ${network.scanner}/address/${token.address}#writeContract`)
  console.log(` - grantRole( ${getRole('BURNER_ROLE')}, ${store.address} )`)
  console.log('')
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().then(() => process.exit(0)).catch(error => {
  console.error(error)
  process.exit(1)
});