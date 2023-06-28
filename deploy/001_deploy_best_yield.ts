import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const byStrategy = await deploy('BestYieldStrategy', {
    from: deployer,
    args: [],
    gasPrice: hre.ethers.utils.parseUnits('59300000', 'wei'),
    gasLimit: 3000000,
    log: true,
  });

  console.log(byStrategy.address);
};

export default func;
func.tags = ['BestYieldStrategy'];
