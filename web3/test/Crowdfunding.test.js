const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CrowdFunding", function () {
    let CrowdFunding;
    let crowdFunding;
    let owner;
    let addr1;
    let addr2;
    let addrs;

    beforeEach(async function () {
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        CrowdFunding = await ethers.getContractFactory("CrowdFunding");
        crowdFunding = await CrowdFunding.deploy();
    });

    describe("Deployment", function () {
        it("Should start with 0 campaigns", async function () {
            expect(await crowdFunding.numberOfCampaigns()).to.equal(0);
        });
    });

    describe("Campaign Creation", function () {
        it("Should create a campaign successfully", async function () {
            const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
            const target = ethers.parseEther("1");

            await expect(crowdFunding.createCampaign(
                owner.address,
                "Test Campaign",
                "Description",
                target,
                deadline,
                "image.jpg"
            ))
                .to.emit(crowdFunding, "CampaignCreated")
                .withArgs(0, owner.address, target, deadline);

            expect(await crowdFunding.numberOfCampaigns()).to.equal(1);
        });

        it("Should fail if deadline is in the past", async function () {
            const deadline = Math.floor(Date.now() / 1000) - 3600;
            const target = ethers.parseEther("1");

            await expect(crowdFunding.createCampaign(
                owner.address,
                "Test",
                "Desc",
                target,
                deadline,
                "img"
            )).to.be.revertedWith("Deadline must be in future");
        });
    });

    describe("Donations", function () {
        it("Should allow donations and update amounts", async function () {
            const deadline = Math.floor(Date.now() / 1000) + 3600;
            await crowdFunding.createCampaign(owner.address, "Test", "Desc", ethers.parseEther("10"), deadline, "img");

            await crowdFunding.connect(addr1).donateToCampaign(0, { value: ethers.parseEther("1") });

            const campaign = await crowdFunding.getCampaign(0);
            expect(campaign.amountCollected).to.equal(ethers.parseEther("1"));

            const [donators, donations] = await crowdFunding.getDonators(0);
            expect(donators[0]).to.equal(addr1.address);
            expect(donations[0]).to.equal(ethers.parseEther("1"));
        });
    });

    describe("Pagination", function () {
        it("Should return correct page of campaigns", async function () {
            const deadline = Math.floor(Date.now() / 1000) + 3600;

            // Create 5 campaigns
            for (let i = 0; i < 5; i++) {
                await crowdFunding.createCampaign(owner.address, `Campaign ${i}`, "Desc", ethers.parseEther("1"), deadline, "img");
            }

            // Get first 2
            const page1 = await crowdFunding.getCampaigns(0, 2);
            expect(page1.length).to.equal(2);
            expect(page1[0].title).to.equal("Campaign 0");
            expect(page1[1].title).to.equal("Campaign 1");

            // Get next 2
            const page2 = await crowdFunding.getCampaigns(2, 2);
            expect(page2.length).to.equal(2);
            expect(page2[0].title).to.equal("Campaign 2");
            expect(page2[1].title).to.equal("Campaign 3");

            // Get last 1
            const page3 = await crowdFunding.getCampaigns(4, 2);
            expect(page3.length).to.equal(1);
            expect(page3[0].title).to.equal("Campaign 4");

            // Get out of bounds
            const page4 = await crowdFunding.getCampaigns(5, 2);
            expect(page4.length).to.equal(0);
        });
    });
});
