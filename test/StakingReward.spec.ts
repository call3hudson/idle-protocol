import { expect } from 'chai';
import { ethers, network } from 'hardhat';
import {
  APIConsumer,
  BestYieldStrategy,
  Vault,
  VGov,
  IWETH,
  StakingReward,
  APIConsumer__factory,
  BestYieldStrategy__factory,
  Vault__factory,
  StakingReward__factory,
} from '../typechain-types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { parseUnits } from 'ethers/lib/utils';

describe('StakingReward', function () {
  let apiConsumer: APIConsumer;
  let byStrategy: BestYieldStrategy;
  let newStrategy: BestYieldStrategy;
  let vault: Vault;
  let staking: StakingReward;
  let weth: IWETH;
  let governance: VGov;

  let owner: SignerWithAddress;
  let user0: SignerWithAddress;
  let user1: SignerWithAddress;

  const v100000 = parseUnits('100000', 18);
  const v10000 = parseUnits('10000', 18);
  const v1000 = parseUnits('1000', 18);
  const v500 = parseUnits('500', 18);
  const v250 = parseUnits('250', 18);
  const v125 = parseUnits('125', 18);
  const v100 = parseUnits('100', 18);
  const v50 = parseUnits('50', 18);
  const v25 = parseUnits('25', 18);
  const v10 = parseUnits('10', 18);

  beforeEach(async () => {
    [owner, user0, user1] = await ethers.getSigners();

    const APIConsumer: APIConsumer__factory = (await ethers.getContractFactory(
      'APIConsumer',
      owner
    )) as APIConsumer__factory;
    apiConsumer = await APIConsumer.connect(owner).deploy();
    await apiConsumer.deployed();

    const BYStrategy: BestYieldStrategy__factory = (await ethers.getContractFactory(
      'BestYieldStrategy',
      owner
    )) as BestYieldStrategy__factory;
    byStrategy = await BYStrategy.connect(owner).deploy();
    await byStrategy.deployed();

    newStrategy = await BYStrategy.connect(owner).deploy();
    await newStrategy.deployed();

    const Vault: Vault__factory = (await ethers.getContractFactory(
      'Vault',
      owner
    )) as Vault__factory;
    vault = await Vault.connect(owner).deploy(byStrategy.address);
    await vault.deployed();

    const StakingReward: StakingReward__factory = (await ethers.getContractFactory(
      'StakingReward',
      owner
    )) as StakingReward__factory;
    staking = await StakingReward.connect(owner).deploy(
      owner.address,
      await vault.WETH(),
      await vault.governance()
    );

    weth = await ethers.getContractAt('IWETH', await vault.WETH());
    governance = await ethers.getContractAt('VGov', await vault.governance());

    await weth.connect(user1).deposit({ value: v1000 });
    await weth.connect(user1).transfer(staking.address, v1000);

    await staking.connect(owner).notifyRewardAmount(v1000);

    await byStrategy.connect(owner).setUser(vault.address);
    await byStrategy.connect(owner).setOracle(apiConsumer.address);
    await newStrategy.connect(owner).setUser(vault.address);
    await newStrategy.connect(owner).setOracle(apiConsumer.address);

    await staking.connect(owner).setRewardsDistribution(vault.address);
    await vault.connect(owner).setStakingContract(staking.address);
  });

  describe('#deposit', () => {
    it('Should check the reward depositing', async () => {
      await expect(vault.connect(user0).deposit({ value: v1000 }))
        .to.emit(vault, 'Deposited')
        .withArgs(user0.address, v1000, v100);

      await vault.connect(owner).invest();

      await expect(vault.connect(user1).deposit({ value: v500 }))
        .to.emit(vault, 'Deposited')
        .withArgs(user1.address, v500, v50.add(5));

      await governance.connect(user0).approve(staking.address, v100);
      await governance.connect(user1).approve(staking.address, v50);

      await staking.connect(user0).stake(v100);
      await staking.connect(user1).stake(v50);

      await vault.connect(owner).startRewardsDistribution();

      await network.provider.send('hardhat_mine', ['0x100']);

      await expect(staking.connect(user0).getReward())
        .to.emit(staking, 'RewardPaid')
        .withArgs(user0.address, ethers.utils.parseUnits('286038415923639400', 0));

      await expect(staking.connect(user1).getReward())
        .to.emit(staking, 'RewardPaid')
        .withArgs(user1.address, ethers.utils.parseUnits('142743622011561700', 0));
    });
  });
});
