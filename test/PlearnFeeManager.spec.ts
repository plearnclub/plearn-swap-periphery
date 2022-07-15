import chai, { expect } from "chai";
import { solidity, MockProvider, createFixtureLoader, deployContract } from "ethereum-waffle";
import { Contract, BigNumber } from "ethers";
import { AddressZero, Zero, MaxUint256 } from "@ethersproject/constants";

import { expandTo18Decimals, getApprovalDigest, mineBlock, MINIMUM_LIQUIDITY } from "./shared/utilities";

import { v3Fixture } from "./shared/fixtures";

chai.use(solidity);

const overrides = {
  gasLimit: 9999999,
};

describe("PlearnFeeManager", () => {
  const provider = new MockProvider({
    ganacheOptions: {
      hardfork: "istanbul",
      mnemonic: "horn horn horn horn horn horn horn horn horn horn horn horn",
      gasLimit: 9999999,
    },
  });
  const [wallet, burnWallet, teamWallet] = provider.getWallets();
  const loadFixture = createFixtureLoader([wallet, burnWallet, teamWallet], provider);

  let PLN: Contract;
  let token1: Contract;
  let token2: Contract;
  let router: Contract;
  let feeHandler: Contract;
  let feeManager: Contract;
  let pair: Contract;
  let pair2: Contract;

  beforeEach(async function () {
    const fixture = await loadFixture(v3Fixture);
    PLN = fixture.token0;
    token1 = fixture.token1;
    token2 = fixture.token2;
    router = fixture.router02;
    feeHandler = fixture.feeHandler;
    feeManager = fixture.feeManager;
    pair = fixture.pair;
    pair2 = fixture.pair2;

    await feeManager.addPair(pair.address);
    // await feeManager.addPair(pair2.address);

    await PLN.approve(router.address, MaxUint256);
    await token1.approve(router.address, MaxUint256);
    await token2.approve(router.address, MaxUint256);

    const plnAmount = expandTo18Decimals(10000);
    const token1Amount = expandTo18Decimals(10000);

    await router.addLiquidity(
      PLN.address,
      token1.address,
      plnAmount,
      token1Amount,
      0,
      0,
      wallet.address,
      MaxUint256,
      overrides,
    );
    await pair.transfer(feeManager.address, expandTo18Decimals(10));

  
    await router.addLiquidity(
      PLN.address,
      token2.address,
      expandTo18Decimals(10000),
      expandTo18Decimals(10000),
      0,
      0,
      wallet.address,
      MaxUint256,
      overrides,
    );
    await pair2.transfer(feeManager.address, expandTo18Decimals(5));
  });

  describe("sendLP", () => {
    it("should Team wallet get 4 LP, fee handler contract get 6 LP and feeManager contract LP balance 0 when processAllFee()", async () => {
      await feeManager.sendLP(pair.address, overrides);
      expect(await pair.balanceOf(teamWallet.address)).to.eq(expandTo18Decimals(4));
      expect(await pair.balanceOf(feeHandler.address)).to.eq(expandTo18Decimals(6));
      expect(await pair.balanceOf(feeManager.address)).to.eq(Zero);
    });
  });

  describe("getLiquidityTokenMinAmount", () => {
    it("should get (A token, B token) min amount 5.97 when remove liquidity 10 LP", async () => {
      // slippageTolerance = 0.5%
      await feeManager.sendLP(pair.address, overrides);
      const LPBurnAmount = expandTo18Decimals(6);
      const [amountAMin, amountBMin] = await feeManager.getLiquidityTokenMinAmount(
        pair.address,
        LPBurnAmount
      );
      expect(amountAMin).to.eq(BigNumber.from("5970000000000000000"));
      expect(amountBMin).to.eq(BigNumber.from("5970000000000000000"));
    });
  });

  describe("getSwapInfo", () => {
    it("getSwapInfo 10 LP", async () => {
      await token1.transfer(feeHandler.address, BigNumber.from("5970000000000000000"));
      const [amountIn, amountOutMin] = await feeManager.getSwapInfo(pair.address);
      expect(amountIn).to.eq(BigNumber.from("5970000000000000000"));
      expect(amountOutMin).to.eq(BigNumber.from("5924739704535599463"));
    });
  });

  describe("processAllFee", () => {
    it("should Team wallet get 4 LP and feeManager contract LP balance 0 when processAllFee() from 10 LP", async () => {
      await feeManager.processAllFee(false, overrides);
      expect(await pair.balanceOf(teamWallet.address)).to.eq(expandTo18Decimals(4));
      expect(await pair.balanceOf(feeManager.address)).to.eq(Zero);
    });

    it("should not process fee because PLN after remove LP less than minimumPlearn", async () => {
      await feeManager.setMinimumPlearn(BigNumber.from("5971000000000000000"), overrides);
      await expect(feeManager.processAllFee(false, overrides)).to.be.revertedWith("invalid amount");
    });

    it("should burn wallet get 11984414381297257556 PLN when processAllFee() from pair 10 LP", async () => {
      await feeManager.processAllFee(false, overrides);
      expect(await PLN.balanceOf(burnWallet.address)).to.eq(BigNumber.from("11984414381297257556"));
      expect(await feeManager.getPairCount()).to.eq(1);
    });

    it("should burn wallet get 17977517977159415073 PLN when processAllFee() from 2 pairs", async () => {
      await feeManager.addPair(pair2.address);
      await feeManager.processAllFee(false, overrides);
      expect(await PLN.balanceOf(burnWallet.address)).to.eq(BigNumber.from("17977517977159415073"));
      expect(await feeManager.getPairCount()).to.eq(2);
    });

    it("should burn wallet get 11984414381297257556 PLN when processAllFee() and PLN in pair2 less than minimumPlearn after remove LP", async () => {
      await feeManager.addPair(pair2.address);
      await feeManager.setMinimumPlearn(BigNumber.from("5970000000000000000"), overrides);
      await feeManager.processAllFee(false, overrides);
      expect(await PLN.balanceOf(burnWallet.address)).to.eq(BigNumber.from("11984414381297257556"));
      expect(await feeManager.getPairCount()).to.eq(2);
    });

  });

});
