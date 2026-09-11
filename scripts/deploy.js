const hre = require("hardhat");
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying TakeCourt with account:", deployer.address);
  console.log("Balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());
  const C = await hre.ethers.getContractFactory("TakeCourt");
  const c = await C.deploy(); await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log("TakeCourt deployed to:", addr);
  console.log("\nNext: paste this into frontend/index.html → CONTRACT_ADDRESS. Update chainId/RPC for mainnet.");
}
main().catch((e) => { console.error(e); process.exit(1); });
