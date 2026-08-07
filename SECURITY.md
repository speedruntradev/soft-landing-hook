# Security model

Status: prototype; not independently audited or deployed.

## Trust and authority

- The immutable PoolManager is the only callback and unlock-callback caller.
- The launcher accepts an unlock callback only from its immutable PoolManager while the keccak256 hash of the exact
  callback bytes matches the active launch. Direct, stale, substituted, and wrong-manager callbacks revert.
- The factory commits the PoolManager, quote asset, controller parameters, both currencies, dynamic fee flag, tick
  spacing, and initial sqrt price to the hook's CREATE2 initcode, then deploys and initializes that exact PoolKey
  atomically.
- No creator, builder, project, administrator, or mutable role can change controller parameters, pause swaps, upgrade
  code, rescue assets, or claim fees.
- The only privileged function is the immutable Programmable owner's claim of its own accrued 10 bps liability, to a
  nonzero destination it selects for that claim.
- The hook exposes no function that initiates a same-pool swap.
- The launcher permanently owns the initial direct PoolManager position and exposes no removal, transfer, approval,
  arbitrary-call, rescue, sweep, upgrade, or LP-fee-claim path.

## Value conservation

- The LP-fee override belongs to LPs and never enters hook custody.
- The hook-owned charge is exactly 10 bps of executed gross quote volume; there is no project charge.
- Fee collection mints quote-denominated PoolManager ERC-6909 claims to the hook.
- The liability key includes canonical PoolId, quote currency, and immutable owner.
- `totalQuoteFeesAccrued` must equal the owner liability after every accrual and claim.
- Redemption burns the exact claims before `take` transfers underlying quote currency.
- Lifetime cumulative rounding remainder survives claims and prevents accepted split swaps from suppressing the fee.
- Atomic launch conservation is `PoolManager token balance + initial buyer token balance + launcher rounding dust =
  fixed total supply`. Native input equals the exact initial-buy amount and the launcher's pre-existing forced native
  balance must be unchanged after launch.

## Callback and lifecycle properties

- Only the canonical dynamic-fee PoolKey reconstructed from constructor immutables is accepted. Initialization takes
  no caller-supplied PoolKey or price, and the callback verifies the committed initial sqrt price.
- The enabled callbacks are exactly `beforeInitialize`, `beforeSwap`, and `afterSwap`, with before/after swap return
  deltas. All other permissions are off.
- Quote-specified partial fills revert atomically, including controller start, flow, and pre-swap liability writes.
- Quote-unspecified paths use the executed `BalanceDelta`.
- A current swap cannot change its own LP fee.
- A block transition runs at most once; same-block swaps only add directional flow.
- Skipped blocks apply bounded decay in constant time.
- After expiry both fees equal base forever and flow state is no longer written.
- The one-sided position must end exactly at the initialized tick. Liquidity and initial buy execute in one unlock;
  only the net token debt and exact native input settle, and PoolManager rejects any nonzero remaining delta.

## Economic threats and accepted limits

An attacker can deliberately execute flow to raise a following block's directional fee. This is a paid congestion
action: it incurs LP fees, the mandatory hook fee, and AMM price impact, but it may still be rational when the attacker
owns liquidity or extracts external MEV. The immutable cap bounds the direct LP-fee impact; it does not make the signal
manipulation-proof.

Raising the sell fee during panic can increase exit cost and create poor optics. Deployments should use a moderate,
public maximum and calibrate targets with simulations. The code enforces a hard 300 bps product maximum.

The one-block lag cannot adapt within the first block. Private bundles, reordering, and a packed one-block snipe remain
possible. The initial fee is therefore part of the mechanism, and Soft Landing should be described as protection
against sustained launch congestion rather than complete anti-MEV protection.

## Unsupported or separately reviewed assets

The settlement assumptions target ordinary ERC-20 or native quote assets. Fee-on-transfer, rebasing, pausable,
blacklistable, callback-capable, or unusually coarse quote tokens require separate review and tests. Gross quote below
1,000 smallest units reverts under the current fee policy.

## Remaining gates

- Independent security review and economic parameter review
- Slither and compiler known-bug disposition on the exact commit
- Mainnet-fork lifecycle and router-parity evidence
- Deterministic deployment address, constructor inputs, runtime hash, and source verification
- Maintainer review of all return-delta accounting
- Production monitoring and incident process

Pinned-fork lifecycle and production Universal Router/V4Planner/Permit2 parity are platform-owned integration gates.
The independent security review is also platform-owned and is explicitly not passed by contributor tests.
