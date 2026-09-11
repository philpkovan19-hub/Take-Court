const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TakeCourt", function () {
  let c, owner, author, a1, a2, b1;
  const FEE = ethers.parseEther("0.005");

  beforeEach(async () => {
    [owner, author, a1, a2, b1] = await ethers.getSigners();
    const F = await ethers.getContractFactory("TakeCourt");
    c = await F.deploy(); await c.waitForDeployment();
  });

  describe("Filing", () => {
    it("files a take with fee", async () => {
      await expect(c.connect(author).fileTake("hot take: pineapple belongs", 3600, { value: FEE }))
        .to.emit(c, "TakeFiled");
      const t = await c.getTake(1);
      expect(t.author).to.equal(author.address);
      expect(t.content).to.equal("hot take: pineapple belongs");
    });
    it("rejects insufficient fee", async () => {
      await expect(c.connect(author).fileTake("x", 3600, { value: 1 })).to.be.revertedWith("Insufficient filing fee");
    });
    it("rejects too-short duration", async () => {
      await expect(c.connect(author).fileTake("x", 60, { value: FEE })).to.be.revertedWith("Duration 1h-30d");
    });
  });

  describe("Voting", () => {
    beforeEach(async () => { await c.connect(author).fileTake("take", 3600, { value: FEE }); });
    it("crowns and bonks add to pools", async () => {
      await c.connect(a1).voteCrown(1, { value: ethers.parseEther("1") });
      await c.connect(b1).voteBonk(1, { value: ethers.parseEther("0.5") });
      const t = await c.getTake(1);
      expect(t.crownPool).to.equal(ethers.parseEther("1"));
      expect(t.bonkPool).to.equal(ethers.parseEther("0.5"));
    });
    it("cannot vote both sides", async () => {
      await c.connect(a1).voteCrown(1, { value: ethers.parseEther("0.1") });
      await expect(c.connect(a1).voteBonk(1, { value: ethers.parseEther("0.1") })).to.be.revertedWith("Cannot vote both sides");
    });
    it("rejects vote after voting ended", async () => {
      await ethers.provider.send("evm_increaseTime", [3601]);
      await ethers.provider.send("evm_mine");
      await expect(c.connect(a1).voteCrown(1, { value: ethers.parseEther("1") })).to.be.revertedWith("Voting ended");
    });
  });

  describe("Adjudicate + claim", () => {
    beforeEach(async () => {
      await c.connect(author).fileTake("take", 3600, { value: FEE });
      await c.connect(a1).voteCrown(1, { value: ethers.parseEther("1") });
      await c.connect(a2).voteCrown(1, { value: ethers.parseEther("3") });
      await c.connect(b1).voteBonk(1, { value: ethers.parseEther("2") });
      await ethers.provider.send("evm_increaseTime", [3601]);
      await ethers.provider.send("evm_mine");
      await c.adjudicate(1);
    });
    it("verdict is Crowned (4 vs 2)", async () => {
      const t = await c.getTake(1);
      expect(t.verdict).to.equal(1); // Crowned
    });
    it("winner claims stake + proportional slice of losers", async () => {
      // losing pool = 2 BOT, fee = 3% = 0.06, distributable = 1.94
      // a1 stake 1/4 of winning pool → payout = 1 + (1 * 1.94 / 4) = 1.485
      const before = await ethers.provider.getBalance(a1.address);
      const tx = await c.connect(a1).claim(1);
      const rc = await tx.wait();
      const gas = rc.gasUsed * rc.gasPrice;
      const after = await ethers.provider.getBalance(a1.address);
      const netGained = after + gas - before;
      expect(netGained).to.equal(ethers.parseEther("1.485"));
    });
    it("loser cannot claim any payout", async () => {
      const before = await ethers.provider.getBalance(b1.address);
      const tx = await c.connect(b1).claim(1);
      const rc = await tx.wait();
      const gas = rc.gasUsed * rc.gasPrice;
      const after = await ethers.provider.getBalance(b1.address);
      expect(after + gas - before).to.equal(0n);
    });
    it("cannot double-claim", async () => {
      await c.connect(a1).claim(1);
      await expect(c.connect(a1).claim(1)).to.be.revertedWith("Already claimed");
    });
  });

  describe("Admin", () => {
    it("owner sets fee", async () => {
      await c.connect(owner).setFilingFee(ethers.parseEther("0.02"));
      expect(await c.filingFee()).to.equal(ethers.parseEther("0.02"));
    });
    it("non-owner cannot", async () => {
      await expect(c.connect(author).setFilingFee(1)).to.be.reverted;
    });
  });
});
