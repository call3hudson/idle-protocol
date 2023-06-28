import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const vault = await deploy('Vault', {
    from: deployer,
    args: ['0xDb033Ff2d322c8997772Bc6BDcda1C6f80568F5d'],
    gasPrice: hre.ethers.utils.parseUnits('59300000', 'wei'),
    gasLimit: 3000000,
    log: true,
  });
};

export default func;
func.tags = ['Vault'];
