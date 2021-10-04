const {
    expect
} = require("chai");
const {
    ethers,
    upgrades
} = require("hardhat");

describe("Test Upgrade Router", function () {

    const MOCK_WBNB_ADDRESS = "0x6d696098d9F8B8533e1Abe94ab6372e987c4A07d";
    const PLEARN_FACTORY_ADDRESS = "0xd21BB000169756FB0A9786BE61FcA80166fCE7a9"
    let creator;

    // `beforeEach` will run before each test, re-deploying the contract every
    // time. It receives a callback, which can be async.
    beforeEach(async function () {
        creator = await ethers.getSigners();
    });


    it("should be upgraded router", async function () {

        //console.log("Deploying PlearnFactory...");
        //const PlearnFactorys = await ethers.getContractFactory("PlearnFactory");
        //const plearnFactory = await PancakeFactorys.deploy(creator.getAddress());
        //console.log("PlearnFactory deployed, address: %s", pancakeFactory.address);

        // Deploying
        console.log("Deploying PlearnRouter02...");
        const PlearnRouter02 = await ethers.getContractFactory("PlearnRouter02");
        const plearnRouter02 = await upgrades.deployProxy(PlearnRouter02, [PLEARN_FACTORY_ADDRESS, MOCK_WBNB_ADDRESS]);
        console.log("PlearnRouter02 deployed, address: %s", plearnRouter02.address);
        console.log("PlearnRouter02 swapFeeReward address: %s", await plearnRouter02.swapFeeReward());

        // Upgrading
        console.log("Upgrading PlearnRouter02...");
        const PlearnRouter02V2 = await ethers.getContractFactory("PlearnRouter02V2");
        const plearnRouter02V2 = await upgrades.upgradeProxy(plearnRouter02.address, PlearnRouter02V2);
        console.log("PlearnRouter02 Upgraded, address: %s", plearnRouter02V2.address);
        console.log("PlearnRouter02 swapFeeReward address: %s", await plearnRouter02V2.swapFeeReward());

    });
});