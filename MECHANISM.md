# Mechanism specification

## Product contract

Soft Landing is a temporary, block-stable congestion controller for one canonical Uniswap v4 launch pool. It measures
executed gross quote throughput, independently for buys and sells. Completed block `N` selects the directional LP fee
for block `N+1`; a swap never changes its own LP fee.

The hook never selectively denies a swap based on wallet identity, holding time, transaction origin, router, buy size,
sell size, or direction. Ordinary core failures still apply. Specified-quote partial fills and quote amounts below the
mandatory fee quantum fail closed rather than use ambiguous accounting.

## Units and immutable configuration

- LP fees (`baseFeePips`, `initialBuyFeePips`, `initialSellFeePips`, `maxFeePips`, `riseAt2xTargetPips`, and
  `decayAtZeroPips`) use Uniswap pips: one unit is `0.0001%`; 100 pips is one basis point.
- `targetQuotePerBlock` and directional flow use the quote token's smallest unit.
- `maxExcessBps` uses basis points of utilization above target and caps counted excess.
- `warmupBlocks` counts active blocks from the first successful canonical-pool swap.
- The product-level maximum LP fee is 30,000 pips (300 bps, or 3%).

Constructor validation requires:

```text
0 < base <= initial buy <= max <= 30,000 pips
0 < base <= initial sell <= max <= 30,000 pips
0 < rise at 2x target <= max - base
0 < decay at zero <= max - base
0 < target quote per block <= 2^128 - 1
0 < max excess bps <= 100,000
0 < warmup blocks <= 1,000,000
```

## Deployment identity and initialization

The factory includes the PoolManager, registrar, quote currency, all controller parameters, both PoolKey currencies,
tick spacing, and initial sqrt price in the hook constructor encoding. The dynamic-fee flag is fixed in the hook's
creation code, and the hook address supplies the PoolKey's hook member. Consequently every launch-defining PoolKey
member and initialization parameter changes the CREATE2 initcode hash and predicted deployment address.

The caller supplies the address mined for the exact launch configuration. The factory recomputes it and reverts with
`LaunchIdentityMismatch` before deployment if any parameter drift produces a different address. After deployment the
factory obtains the PoolKey from hook immutables and calls a no-argument registration function; callers cannot swap in
a different PoolKey or initial price between address mining and initialization.

## Economic direction

Direction is defined by the quote asset, not by token ordering:

```text
buy  = quote is the swap input
sell = quote is the swap output
```

Equivalently, with `quoteIsCurrency0` already bound:

```text
isBuy = params.zeroForOne == quoteIsCurrency0
```

The fee returned by `beforeSwap` is an LP-fee override. The LP fee is paid in the swap input asset, so a buy normally
pays it in quote and a sell normally pays it in the launch token.

## Directional update formula

For a direction, let `F` be executed gross quote flow in the completed block, `T` the target, `f` the current fee,
`b` the base fee, `m` the maximum, `r` the increase at 2x target, `d` the zero-flow decay, and `Emax` the counted
excess cap:

```text
if F > T:
    excessBps = min(floor((F - T) * 10,000 / T), Emax)
    increase   = ceil(excessBps * r / 10,000)
    nextFee    = min(m, f + increase)
else:
    slackBps = floor((T - F) * 10,000 / T)
    decrease = ceil(slackBps * d / 10,000)
    nextFee  = max(b, f - decrease)
```

Exactly target leaves the fee unchanged. Larger flow cannot produce a lower next fee. Zero flow applies the full
configured decay. All multiplication uses Uniswap `FullMath` with capped ratios.

## Block transition and skipped blocks

The first successful swap in block `B` starts the controller:

```text
startBlock = B
lastObservedBlock = B
endBlockExclusive = B + warmupBlocks
```

The first swap in a later active block applies the previous observed block once, then applies every intervening empty
block as zero-flow decay in one saturating operation. No loop depends on the block gap:

```text
emptyBlocks = B - lastObservedBlock - 1
fee = max(baseFee, fee - emptyBlocks * decayAtZero)
```

Flow counters are then cleared and `lastObservedBlock` becomes `B`. Later swaps in the same block only add executed
gross quote flow. Thus each direction has one stable fee for the entire block.

## Expiry

The controller is active while:

```text
block.number < startBlock + warmupBlocks
```

The first swap at or after the exclusive end permanently sets both directional fees to base, clears both flow
counters, and sets `expired = true`. After expiry the controller performs no flow writes. The pool remains a dynamic-fee
pool at the protocol level, but the effective LP fee is permanently fixed at base.

The mandatory Programmable quote-volume fee continues after controller expiry.

## Programmable fee

The project-selected hook-owned charge is zero. Under `programmable-volume-fee-v1@1.1.0`:

```text
selected total = 0
effective total = max(0, 1,000) = 1,000 hundredths of a bip = 10 bps
Programmable = 10 bps
project = 0
```

The basis is executed gross quote-side volume. Quote-specified modes collect before the core swap and verify the
executed pool delta after it; quote-unspecified modes collect after the core swap from `BalanceDelta`. Positive gross
amounts below 1,000 smallest units revert. A single lifetime numerator remainder prevents split-swap rounding bypass:

```text
liability_n = floor(sum(gross_i * 1,000) / 1,000,000)
```

Claims do not reset the remainder. The hook holds quote-denominated PoolManager ERC-6909 claims. Only
`0x4957f49620AFf3Adbbe8195a4f633E49cc93376c` may redeem its liability, to itself or a nonzero destination selected for
that claim.

## Worked controller examples

Unless stated otherwise:

```text
base 30 bps; initial 100 bps; maximum 300 bps
target 10 ETH; rise at 2x target 50 bps; zero-flow decay 25 bps
```

1. `F = 10 ETH`: fee remains 100 bps.
2. `F = 20 ETH`: excess is 100%; fee rises 50 bps to 150 bps.
3. `F = 25 ETH`: excess is 150%; fee rises 75 bps to 175 bps.
4. `F = 2 ETH`: slack is 80%; fee falls 20 bps to 80 bps.
5. `F = 0`: fee falls 25 bps to 75 bps.
6. Three empty blocks after a 175 bps fee: fee falls directly to 100 bps.
7. A 1,000% excess with `maxExcessBps = 30,000`: counted excess is capped at 300%, so the block increase is 150 bps.
8. A computed fee above 300 bps clamps to 300 bps; a decay below 30 bps clamps to 30 bps.

## Same-block and MEV trade-off

Every direction's fee is fixed within a block. This prevents a swap from raising its own fee and prevents transaction
ordering from assigning different controller fees to same-direction swaps. It also means a packed first-block bundle
pays the configured initial fee and adaptive feedback begins only in the next block. Soft Landing prices sustained
directional launch congestion; it is not a complete response to one-block sniping.
