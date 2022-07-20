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

describe('ERC721Staking Tests', function () {
  before(async function() {
    const signers = await ethers.getSigners()

    const token = await deploy('ERC20Soulbound', signers[0].address)
    await bindContract('withToken', 'ERC20Soulbound', token, signers)

    const nft = await deploy('ERC721Mock', '3Landers', '3L')
    await bindContract('withNFT', 'ERC721Mock', nft, signers)

    const staking = await deploy('ERC721Staking', nft.address, token.address, signers[0].address)
    await bindContract('withStaking', 'ERC721Staking', staking, signers)

    const [ admin, user1, user2 ] = signers

    //make admin MINTER_ROLE, PAUSER_ROLE, BURNER_ROLE
    await admin.withToken.grantRole(getRole('MINTER_ROLE'), admin.address)
    await admin.withToken.grantRole(getRole('PAUSER_ROLE'), admin.address)
    await admin.withToken.grantRole(getRole('BURNER_ROLE'), admin.address)
    //make admin STAKER_ROLE, CURATOR_ROLE
    await admin.withStaking.grantRole(getRole('STAKER_ROLE'), admin.address)
    await admin.withStaking.grantRole(getRole('CURATOR_ROLE'), admin.address)
    //make staking MINTER_ROLE
    await admin.withToken.grantRole(getRole('MINTER_ROLE'), staking.address)

    //give users NFTs
    await admin.withNFT.mint(user1.address, 1)
    await admin.withNFT.mint(user1.address, 2)
    await admin.withNFT.mint(user1.address, 3)
    await admin.withNFT.mint(user1.address, 4)
    await admin.withNFT.mint(user1.address, 5)

    await admin.withNFT.mint(user2.address, 6)
    await admin.withNFT.mint(user2.address, 7)
    await admin.withNFT.mint(user2.address, 8)
    await admin.withNFT.mint(user2.address, 9)

    this.signers = { admin, user1, user2 }
  })

  it('Should get nfts available for staking', async function() {
    const { user1, user2 } = this.signers
    const tokens1 = await user1.withStaking.available(user1.address)
    expect(tokens1[0]).to.equal(1)
    expect(tokens1[1]).to.equal(2)
    expect(tokens1[2]).to.equal(3)
    expect(tokens1[3]).to.equal(4)
    expect(tokens1[4]).to.equal(5)
    expect(tokens1.length).to.equal(5)

    const tokens2 = await user2.withStaking.available(user2.address)
    expect(tokens2[0]).to.equal(6)
    expect(tokens2[1]).to.equal(7)
    expect(tokens2[2]).to.equal(8)
    expect(tokens2[3]).to.equal(9)
    expect(tokens2.length).to.equal(4)
  })

  it('Should stake NFT', async function() {
    const { admin, user1 } = this.signers
    //approve to be handled by the staking contract
    await user1.withNFT.approve(user1.withStaking.address, 1)
    await user1.withNFT.approve(user1.withStaking.address, 2)
    await user1.withNFT.approve(user1.withStaking.address, 3)

    //not staking so nothing would be released
    expect(await admin.withStaking.released(1)).to.equal(0)
    expect(await admin.withStaking.released(2)).to.equal(0)
    expect(await admin.withStaking.released(3)).to.equal(0)
    expect(await admin.withStaking.released(4)).to.equal(0)
    expect(await admin.withStaking.released(5)).to.equal(0)
    //not staking so nothing is releaseable
    expect(await admin.withStaking.releaseable(1)).to.equal(0)
    expect(await admin.withStaking.releaseable(2)).to.equal(0)
    expect(await admin.withStaking.releaseable(3)).to.equal(0)
    expect(await admin.withStaking.releaseable(4)).to.equal(0)
    expect(await admin.withStaking.releaseable(5)).to.equal(0)
    //not staking so no date recorded
    expect(await admin.withStaking.stakedSince(1)).to.equal(0)
    expect(await admin.withStaking.stakedSince(2)).to.equal(0)
    expect(await admin.withStaking.stakedSince(3)).to.equal(0)
    expect(await admin.withStaking.stakedSince(4)).to.equal(0)
    expect(await admin.withStaking.stakedSince(5)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(1)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(2)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(3)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(4)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(5)).to.equal(0)
    
    //stake 1
    await user1.withStaking['stake(uint256[])']([1])
    expect((
      await user1.withStaking.available(user1.address)
    ).length).to.equal(4)
    expect((
      await user1.withStaking.staked(user1.address)
    ).length).to.equal(1)

    //stake 2, 3
    await user1.withStaking['stake(uint256[])']([2, 3])
    expect((
      await user1.withStaking.available(user1.address)
    ).length).to.equal(2)
    expect((
      await user1.withStaking.staked(user1.address)
    ).length).to.equal(3)

    //admin stakes 4
    await user1.withNFT.approve(user1.withStaking.address, 4)
    await admin.withStaking['stake(address,uint256[])'](user1.address, [4])
    expect((
      await user1.withStaking.available(user1.address)
    ).length).to.equal(1)
    expect((
      await user1.withStaking.staked(user1.address)
    ).length).to.equal(4)

    //should be last date
    expect(await admin.withStaking.released(1)).to.be.above(0)
    expect(await admin.withStaking.released(2)).to.be.above(0)
    expect(await admin.withStaking.released(3)).to.be.above(0)
    expect(await admin.withStaking.released(4)).to.be.above(0)
    expect(await admin.withStaking.released(5)).to.to.equal(0)
    //should be releaseable now
    expect(await admin.withStaking.releaseable(1)).to.be.above(0)
    expect(await admin.withStaking.releaseable(2)).to.be.above(0)
    expect(await admin.withStaking.releaseable(3)).to.be.above(0)
    //expect(await admin.withStaking.releaseable(4)).to.be.above(0)
    expect(await admin.withStaking.releaseable(5)).to.equal(0)
    //not staking so no date recorded
    expect(await admin.withStaking.stakedSince(1)).to.be.above(0)
    expect(await admin.withStaking.stakedSince(2)).to.be.above(0)
    expect(await admin.withStaking.stakedSince(3)).to.be.above(0)
    expect(await admin.withStaking.stakedSince(4)).to.be.above(0)
    expect(await admin.withStaking.stakedSince(5)).to.equal(0)
    //did not unstake yet so no history
    expect(await admin.withStaking.stakedLongest(1)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(2)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(3)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(4)).to.equal(0)
    expect(await admin.withStaking.stakedLongest(5)).to.equal(0)
  })

  it('Should not stake NFT', async function() {
    const { admin, user1 } = this.signers

    await expect(//not approved
      admin.withStaking['stake(address,uint256[])'](user1.address, [5])
    ).to.be.revertedWith('ERC721: transfer caller is not owner nor approved')

    await expect(//already staking
      user1.withStaking['stake(uint256[])']([1])
    ).to.be.revertedWith('InvalidCall()')

    await expect(//not owner
      admin.withStaking['stake(uint256[])']([5])
    ).to.be.revertedWith('ERC721: transfer caller is not owner nor approved')
  })

  it('Should release', async function() {
    const { admin, user1 } = this.signers

    this.since = await admin.withStaking.stakedSince(1)
    this.longest = await admin.withStaking.stakedLongest(1)
    this.balance = await admin.withToken.balanceOf(user1.address)

    await user1.withStaking['release(uint256[])']([1, 2])
    expect(//user to have tokens now
      await user1.withToken.balanceOf(user1.address)
    ).to.be.above(this.balance)
    expect(//staking since to not change
      await admin.withStaking.stakedSince(1)
    ).to.equal(this.since)
    expect(//longest should still be 0
      await admin.withStaking.stakedLongest(1)
    ).to.equal(0)
  })

  it('Should fastforward 30 days later', async function() {
    await ethers.provider.send('evm_mine');
    await ethers.provider.send('evm_increaseTime', [(3600 * 24 * 30)]); 
    await ethers.provider.send('evm_mine');
  })

  it('Should unstake', async function() {
    const { admin, user1 } = this.signers

    await user1.withStaking['unstake(uint256[])']([1, 2])
    expect(//user to have more tokens than before
      await user1.withToken.balanceOf(user1.address)
    ).to.be.above(this.balance)
    expect(//staking should reset
      await admin.withStaking.stakedSince(1)
    ).to.equal(0)
    expect(//should be something now
      await admin.withStaking.stakedLongest(1)
    ).to.be.above(this.longest)
  })
})