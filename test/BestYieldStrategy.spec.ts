import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  APIConsumer,
  APIConsumer__factory,
  BestYieldStrategy,
  BestYieldStrategy__factory,
} from '../typechain-types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { parseUnits } from 'ethers/lib/utils';

describe('BestYieldStrategy', function () {
  let apiConsumer: APIConsumer;
  let byStrategy: BestYieldStrategy;

  let owner: SignerWithAddress;
  let user0: SignerWithAddress;

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
    [owner, user0] = await ethers.getSigners();

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

    await byStrategy.connect(owner).setUser(user0.address);
    await byStrategy.connect(owner).setOracle(apiConsumer.address);
  });

  describe('receive', () => {
    it('Should prevent non-WETH deposit ether', async () => {
      await expect(user0.sendTransaction({ value: v100, to: byStrategy.address })).to.revertedWith(
        'Strategy: Only WETH can send ether'
      );
    });
  });

  describe('#mint', () => {
    it('Should check the initial values', async () => {
      await expect(byStrategy.connect(user0).mint({ value: 0 })).to.revertedWith(
        'Strategy: Invalid Ether amount'
      );
    });

    it('Should prevent non-vault contract to call function', async () => {
      await expect(byStrategy.connect(owner).mint({ value: 0 })).to.revertedWith(
        'Strategy: Only user can call this function'
      );
    });

    it('Should check the valid minting', async () => {
      await expect(byStrategy.connect(user0).mint({ value: v1000 }))
        .to.emit(byStrategy, 'Minted')
        .withArgs(user0.address, v1000, parseUnits('978664748246054760918', 0));
    });
  });

  describe('#withdraw', () => {
    it('Should check the initial values', async () => {
      await expect(byStrategy.connect(user0).withdraw(0)).to.revertedWith(
        'Strategy: Invalid amount'
      );
    });

    it('Should prevent non-vault contract to call function', async () => {
      await expect(byStrategy.connect(owner).withdraw(0)).to.revertedWith(
        'Strategy: Only user can call this function'
      );
    });

    it('Should check the insufficiency', async () => {
      await byStrategy.connect(user0).mint({ value: v1000 });
      await expect(byStrategy.connect(user0).withdraw(v10000)).to.revertedWith(
        'Strategy: Insufficient amount'
      );
    });

    it('Should check the valid withdraw', async () => {
      await byStrategy.connect(user0).mint({ value: v1000 });

      await expect(byStrategy.connect(user0).withdraw(v500))
        .to.emit(byStrategy, 'Withdrawn')
        .withArgs(user0.address, v500, parseUnits('489332374123027380460', 0));
    });
  });

  describe('#withdrawAll', () => {
    it('Should check the insufficiency', async () => {
      await expect(byStrategy.connect(user0).withdrawAll()).to.revertedWith(
        'Strategy: Provide underlying token first'
      );
    });

    it('Should prevent non-vault contract to call function', async () => {
      await expect(byStrategy.connect(owner).withdrawAll()).to.revertedWith(
        'Strategy: Only user can call this function'
      );
    });

    it('Should check the valid withdraw', async () => {
      await byStrategy.connect(user0).mint({ value: v1000 });

      await expect(byStrategy.connect(user0).withdrawAll())
        .to.emit(byStrategy, 'WithdrawnAll')
        .withArgs(
          user0.address,
          parseUnits('999999999999999999999', 0),
          parseUnits('978664748246054760918', 0)
        );
    });
  });

  describe('#getExpectedWithdraw', () => {
    it('Should prevent non-vault contract to call function', async () => {
      await expect(byStrategy.connect(owner).getExpectedWithdraw()).to.revertedWith(
        'Strategy: Only user can call this function'
      );
    });
  });

  describe('#setUser', () => {
    it('Should check if non-owner can set new user', async () => {
      await expect(byStrategy.connect(user0).setUser(user0.address)).revertedWith(
        'Ownable: caller is not the owner'
      );
    });

    it('Should check the valid user reset', async () => {
      await expect(byStrategy.setUser(owner.address))
        .to.emit(byStrategy, 'NewUser')
        .withArgs(owner.address, user0.address, owner.address);
    });
  });

  describe('#setOracle', () => {
    it('Should check if non-owner can set new oracle', async () => {
      await expect(byStrategy.connect(user0).setOracle(user0.address)).revertedWith(
        'Ownable: caller is not the owner'
      );
    });

    it('Should check the valid oracle reset', async () => {
      await expect(byStrategy.setOracle(user0.address))
        .to.emit(byStrategy, 'NewOracle')
        .withArgs(owner.address, apiConsumer.address, user0.address);
    });
  });
});
