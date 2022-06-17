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

  let token0: Contract;
  let token1: Contract;
  let router: Contract;
  let feeHandler: Contract;
  let feeManager: Contract;
  let pair: Contract;

  beforeEach(async function () {
    const fixture = await loadFixture(v3Fixture);
    token0 = fixture.token0;
    token1 = fixture.token1;
    router = fixture.router02;
    feeHandler = fixture.feeHandler;
    feeManager = fixture.feeManager;
    pair = fixture.pair;

    await feeManager.addPair(pair.address);

    await token0.approve(router.address, MaxUint256);
    await token1.approve(router.address, MaxUint256);

    const token0Amount = expandTo18Decimals(10000);
    const token1Amount = expandTo18Decimals(10000);

    await router.addLiquidity(
      token0.address,
      token1.address,
      token0Amount,
      token1Amount,
      0,
      0,
      wallet.address,
      MaxUint256,
      overrides,
    );
    await pair.transfer(feeManager.address, expandTo18Decimals(10));
    console.log("Reserves", (await pair.getReserves()).toString());
    console.log("totalSupply", (await pair.totalSupply()).toString());
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
    it("should get (A token, B token) min amount 5.97 when remove liquidity 6 LP", async () => {
      const LPAmount = expandTo18Decimals(6);
      const totalSupply = await pair.totalSupply();

      const [reserve0, reserve1,] = await pair.getReserves();
      const [amountAMin, amountBMin] = await feeManager.getLiquidityTokenMinAmount(reserve0, reserve1, LPAmount, totalSupply);
      expect(amountAMin).to.eq(BigNumber.from("5970000000000000000"));
      expect(amountBMin).to.eq(BigNumber.from("5970000000000000000"));
    });
  });

  describe("processAllFee", () => {
    it("should Team wallet get 4 LP and feeManager contract LP balance 0 when processAllFee() from 10 LP", async () => {
      await feeManager.processAllFee(false, overrides);
      expect(await pair.balanceOf(teamWallet.address)).to.eq(expandTo18Decimals(4));
      expect(await pair.balanceOf(feeManager.address)).to.eq(Zero);
    });

    it("should burn wallet get 11984414381297257556 token0 when processAllFee() from 10 LP", async () => {
      await feeManager.processAllFee(false, overrides);
      expect(await token0.balanceOf(burnWallet.address)).to.eq(BigNumber.from("11984414381297257556"));
      expect(await feeManager.getPairCount()).to.eq(1);
    });
  });

});
