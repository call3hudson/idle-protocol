import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  APIConsumer,
  BestYieldStrategy,
  Vault,
  APIConsumer__factory,
  BestYieldStrategy__factory,
  Vault__factory,
} from '../typechain-types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { parseUnits } from 'ethers/lib/utils';

describe('Vault', function () {
  let apiConsumer: APIConsumer;
  let byStrategy: BestYieldStrategy;
  let newStrategy: BestYieldStrategy;
  let vault: Vault;

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

    await byStrategy.connect(owner).setUser(vault.address);
    await byStrategy.connect(owner).setOracle(apiConsumer.address);
    await newStrategy.connect(owner).setUser(vault.address);
    await newStrategy.connect(owner).setOracle(apiConsumer.address);
  });

  describe('constructor', () => {
    it('Should check the initial value', async () => {
      expect(await vault.strategy()).to.be.eq(byStrategy.address);
    });
  });

  describe('receive', () => {
    it('Should prevent non-strategy deposit ether', async () => {
      await expect(user0.sendTransaction({ value: v100, to: vault.address })).to.revertedWith(
        'WETH: Only strategy can send ether'
      );
    });
  });

  describe('#deposit', () => {
    it('Should check the initial values', async () => {
      await expect(vault.deposit({ value: 0 })).to.revertedWith(
        'Vault: You must provide ether to deposit'
      );
    });

    it('Should check the valid depositing', async () => {
      await expect(vault.connect(user0).deposit({ value: v1000 }))
        .to.emit(vault, 'Deposited')
        .withArgs(user0.address, v1000, v100);
    });

    it('Should check the multiple depositing', async () => {
      await expect(vault.connect(user0).deposit({ value: v1000 }))
        .to.emit(vault, 'Deposited')
        .withArgs(user0.address, v1000, v100);

      await vault.connect(owner).invest();

      await expect(vault.connect(user1).deposit({ value: v500 }))
        .to.emit(vault, 'Deposited')
        .withArgs(user1.address, v500, v50);
    });
  });

  describe('#withdraw', () => {
    it('Should check the initial values', async () => {
      await expect(vault.withdraw(0)).to.revertedWith('Vault: Invalid yETH to withdraw');
    });

    it('Should check the insufficiency', async () => {
      await vault.connect(user0).deposit({ value: v1000 });
      await expect(vault.withdraw(v1000)).to.revertedWith('Vault: Insufficient yETH');
    });

    it('Should check the valid withdrawing before invest', async () => {
      const original = await user0.getBalance();

      await vault.connect(user0).deposit({ value: v1000 });

      await expect(vault.connect(user0).withdraw(v100))
        .to.emit(vault, 'Withdrawn')
        .withArgs(user0.address, v1000, v100);

      expect(await vault.balanceOf(user0.address)).to.be.eq(0);
    });

    it('Should check the valid withdrawing after invest', async () => {
      const original = await user0.getBalance();

      await vault.connect(user0).deposit({ value: v1000 });
      await vault.connect(owner).invest();

      await expect(vault.connect(user0).withdraw(v100))
        .to.emit(vault, 'Withdrawn')
        .withArgs(user0.address, parseUnits('999999999999999999999', 0), v100);

      expect(await vault.balanceOf(user0.address)).to.be.eq(0);
    });
  });

  describe('#invest', () => {
    it('Should prevent non-owner call this function', async () => {
      await expect(vault.connect(user0).invest()).to.revertedWith(
        'Ownable: caller is not the owner'
      );
    });

    it('Should prevent zero invest', async () => {
      await expect(vault.invest()).to.revertedWith('Vault: No ether to invest');
    });

    it('Should check the valid invest', async () => {
      await vault.connect(user0).deposit({ value: v1000 });

      const expectedAmount = (await ethers.provider.getBalance(vault.address)).mul(9).div(10);
      await expect(vault.invest())
        .to.emit(vault, 'Invested')
        .withArgs(owner.address, expectedAmount);
    });
  });

  describe('#rebalance', () => {
    it('Should prevent non-owner call this function', async () => {
      await expect(vault.connect(user0).rebalance()).to.revertedWith(
        'Ownable: caller is not the owner'
      );
    });

    it('Should prevent zero rebalance', async () => {
      await expect(vault.rebalance()).to.revertedWith('Vault: No ether to rebalance');
    });

    it('Should check the valid rebalance', async () => {
      await vault.connect(user0).deposit({ value: v1000 });
      await vault.invest();

      await vault.connect(user0).withdraw(v10.div(2));
      await expect(vault.rebalance())
        .to.emit(vault, 'Rebalanced')
        .withArgs(owner.address, parseUnits('44999999999999999999', 0));
    });
  });

  describe('#changeStrategy', () => {
    it('Should prevent non-owner call this function', async () => {
      await expect(vault.connect(user0).changeStrategy(newStrategy.address)).to.revertedWith(
        'Ownable: caller is not the owner'
      );
    });

    it('Should check the valid strategy', async () => {
      await vault.connect(user0).deposit({ value: v1000 });
      await vault.connect(owner).invest();

      await expect(vault.connect(owner).changeStrategy(newStrategy.address))
        .to.emit(vault, 'StrategyChanged')
        .withArgs(owner.address, byStrategy.address, newStrategy.address);

      expect(await ethers.provider.getBalance(vault.address)).to.be.eq(
        parseUnits('999999999999999999999', 0)
      );
    });
  });
});
