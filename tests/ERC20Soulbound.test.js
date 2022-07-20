const { expect } = require('chai');
require('dotenv').config()

if (process.env.BLOCKCHAIN_NETWORK != 'hardhat') {
  console.error('Exited testing with network:', process.env.BLOCKCHAIN_NETWORK)
  process.exit(1);
}

async function deploy(name, ...params) {
  //deploy the contract
  const ContractFactory = await ethers.getContractFactory(name);
  const contract = await ContractFactory.deploy(...params);
  await contract.deployed();

  return contract;
}

async function bindContract(key, name, contract, signers) {
  //attach contracts
  for (let i = 0; i < signers.length; i++) {
    const Contract = await ethers.getContractFactory(name, signers[i]);
    signers[i][key] = await Contract.attach(contract.address);
  }

  return signers;
}

function getRole(name) {
  if (!name || name === 'DEFAULT_ADMIN_ROLE') {
    return '0x0000000000000000000000000000000000000000000000000000000000000000';
  }

  return '0x' + Buffer.from(ethers.utils.solidityKeccak256(['string'], [name]).slice(2), 'hex').toString('hex');
}

describe('ERC20Soulbound Tests', function () {
  before(async function() {
    const signers = await ethers.getSigners()

    const token = await deploy('ERC20Soulbound', signers[0].address)
    await bindContract('withToken', 'ERC20Soulbound', token, signers)

    const [ admin, user1, user2 ] = signers

    //make admin MINTER_ROLE, PAUSER_ROLE, BURNER_ROLE
    await admin.withToken.grantRole(getRole('MINTER_ROLE'), admin.address)
    await admin.withToken.grantRole(getRole('PAUSER_ROLE'), admin.address)
    await admin.withToken.grantRole(getRole('BURNER_ROLE'), admin.address)

    this.signers = { admin, user1, user2 }
  })

  it('Should mint', async function() {
    const { admin, user1, user2 } = this.signers

    await admin.withToken.mint(user1.address, 1000)
    await admin.withToken.mint(user2.address, 2000)

    expect(
      await admin.withToken.balanceOf(user1.address)
    ).to.equal(1000)

    expect(
      await admin.withToken.balanceOf(user2.address)
    ).to.equal(2000)
  })

  it('Should not transfer', async function() {
    const { admin, user1, user2 } = this.signers

    await expect(//soulbound
      user1.withToken.transferFrom(user1.address, user2.address, 100)
    ).to.be.revertedWith('InvalidCall()')

    await user1.withToken.approve(admin.address, 100)

    await expect(//soulbound
      admin.withToken.transferFrom(user1.address, user2.address, 10)
    ).to.be.revertedWith('InvalidCall()')
  })

  it('Should burn', async function() {
    const { admin, user1, user2 } = this.signers
    
    await user1.withToken['burn(uint256)'](1000)
    expect(
      await admin.withToken.balanceOf(user1.address)
    ).to.equal(0)

    await expect(//permissions
      user1.withToken['burn(address,uint256)'](user2.address, 2000)
    ).to.be.revertedWith('InvalidCall()')

    await admin.withToken['burn(address,uint256)'](user2.address, 2000)
    expect(
      await admin.withToken.balanceOf(user2.address)
    ).to.equal(0)
  })
})