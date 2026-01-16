const hre = require("hardhat");

async function main() {
    console.log("Deploying Crowdfunding contract...");

    const crowdfund = await hre.ethers.deployContract("CrowdFunding");

    await crowdfund.waitForDeployment();

    const address = await crowdfund.getAddress();

    console.log(`Crowdfunding deployed to: ${address}`);
    console.log("Please update 'CONTRACT_ADDRESS' in 'client/src/blockchain/config.js' with this address.");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
