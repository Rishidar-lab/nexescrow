import { expect } from "chai";
import { network } from "hardhat";

// Hardhat 3: use network.create() per test suite, not network.connect()
const conn = await network.create();
const { ethers } = conn;

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function getTimestamp(): Promise<number> {
  const block = await ethers.provider.getBlock("latest");
  return block!.timestamp;
}

async function increaseTimeTo(ts: number): Promise<void> {
  await conn.provider.request({ method: "evm_setNextBlockTimestamp", params: [ts] });
  await conn.provider.request({ method: "evm_mine", params: [] });
}

// ─── Test suite ───────────────────────────────────────────────────────────────

describe("NexEscrow", function () {
  let reputationRegistry: any;
  let escrow: any;
  let owner: any, payer: any, payee: any, arbiter: any, malicious: any;

  beforeEach(async function () {
    [owner, payer, payee, arbiter, malicious] = await ethers.getSigners();

    const ReputationRegistry = await ethers.getContractFactory("ReputationRegistry");
    reputationRegistry = await ReputationRegistry.deploy();
    await reputationRegistry.waitForDeployment();

    const Escrow = await ethers.getContractFactory("Escrow");
    escrow = await Escrow.deploy(await reputationRegistry.getAddress());
    await escrow.waitForDeployment();

    await reputationRegistry.setEscrowContract(await escrow.getAddress());
  });

  // ─── Happy path ───────────────────────────────────────────────────────────

  describe("Happy Path", function () {
    it("create → fund → release: payee receives NEX, reputation incremented for both", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      const createTx = await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline);
      const createReceipt = await createTx.wait();
      expect(createReceipt.status).to.equal(1);

      const fundTx = await escrow.connect(payer).fund(1, { value: amount });
      await fundTx.wait();

      const info = await escrow.escrows(1);
      expect(info.state).to.equal(1n); // Funded

      const initialPayeeBalance = await ethers.provider.getBalance(payee.address);
      const releaseTx = await escrow.connect(payer).release(1);
      await releaseTx.wait();

      const finalPayeeBalance = await ethers.provider.getBalance(payee.address);
      expect(finalPayeeBalance - initialPayeeBalance).to.equal(amount);

      const releasedInfo = await escrow.escrows(1);
      expect(releasedInfo.state).to.equal(2n); // Released

      const payerRep = await reputationRegistry.reputationOf(payer.address);
      expect(payerRep.count).to.equal(1n);
      expect(payerRep.volume).to.equal(amount);

      const payeeRep = await reputationRegistry.reputationOf(payee.address);
      expect(payeeRep.count).to.equal(1n);
      expect(payeeRep.volume).to.equal(amount);
    });
  });

  // ─── Refunds ─────────────────────────────────────────────────────────────

  describe("Refunds", function () {
    it("payer cannot refund before deadline", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();

      await expect(escrow.connect(payer).refund(1)).to.revert(ethers);
    });

    it("payer can refund after deadline", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();

      await increaseTimeTo(deadline + 2);

      const initialPayerBalance = await ethers.provider.getBalance(payer.address);
      const refundTx = await escrow.connect(payer).refund(1);
      const receipt = await refundTx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;

      const finalPayerBalance = await ethers.provider.getBalance(payer.address);
      expect(finalPayerBalance + gasUsed - initialPayerBalance).to.equal(amount);

      const info = await escrow.escrows(1);
      expect(info.state).to.equal(3n); // Refunded
    });

    it("arbiter can refund at any time", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();
      await (await escrow.connect(arbiter).refund(1)).wait();

      const info = await escrow.escrows(1);
      expect(info.state).to.equal(3n); // Refunded
    });
  });

  // ─── Disputes ────────────────────────────────────────────────────────────

  describe("Disputes", function () {
    it("payer can dispute; only arbiter can then release or refund", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();

      await (await escrow.connect(payer).dispute(1)).wait();
      let info = await escrow.escrows(1);
      expect(info.state).to.equal(4n); // Disputed

      await expect(escrow.connect(payer).release(1)).to.revert(ethers);

      await (await escrow.connect(arbiter).release(1)).wait();
      info = await escrow.escrows(1);
      expect(info.state).to.equal(2n); // Released
    });

    it("payee can also raise a dispute", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("0.5");

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();

      await (await escrow.connect(payee).dispute(1)).wait();
      const info = await escrow.escrows(1);
      expect(info.state).to.equal(4n); // Disputed
    });

    it("cannot dispute without an arbiter", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      await (await escrow.connect(payer).createEscrow(payee.address, ethers.ZeroAddress, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();

      await expect(escrow.connect(payer).dispute(1)).to.revert(ethers);
    });
  });

  // ─── Edge cases & security ───────────────────────────────────────────────

  describe("Edge Cases and Security", function () {
    it("double-fund reverts", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();

      await expect(escrow.connect(payer).fund(1, { value: amount })).to.revert(ethers);
    });

    it("fund with zero value reverts", async function () {
      const deadline = (await getTimestamp()) + 3600;

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await expect(escrow.connect(payer).fund(1, { value: 0 })).to.revert(ethers);
    });

    it("unauthorized release reverts", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();

      await expect(escrow.connect(malicious).release(1)).to.revert(ethers);
    });

    it("unauthorized refund reverts", async function () {
      const deadline = (await getTimestamp()) + 3600;
      const amount = ethers.parseEther("1.0");

      await (await escrow.connect(payer).createEscrow(payee.address, arbiter.address, deadline)).wait();
      await (await escrow.connect(payer).fund(1, { value: amount })).wait();

      await expect(escrow.connect(malicious).refund(1)).to.revert(ethers);
    });

    it("createEscrow with zero payee reverts", async function () {
      const deadline = (await getTimestamp()) + 3600;
      await expect(
        escrow.connect(payer).createEscrow(ethers.ZeroAddress, arbiter.address, deadline)
      ).to.revert(ethers);
    });

    it("createEscrow with past deadline reverts", async function () {
      const pastDeadline = (await getTimestamp()) - 1;
      await expect(
        escrow.connect(payer).createEscrow(payee.address, arbiter.address, pastDeadline)
      ).to.revert(ethers);
    });

    it("direct call to recordSettlement reverts", async function () {
      await expect(
        reputationRegistry.connect(malicious).recordSettlement(payer.address, payee.address, 100)
      ).to.revert(ethers);
    });

    it("setEscrowContract can only be called once", async function () {
      await expect(
        reputationRegistry.connect(owner).setEscrowContract(malicious.address)
      ).to.revert(ethers);
    });
  });
});
