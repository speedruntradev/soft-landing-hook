# Soft Landing

**Block-stable directional congestion pricing for the unstable launch phase of a Uniswap v4 pool.**

Soft Landing gives buy-side and sell-side quote flow independent throughput targets. A completed block above its
directional target raises only that direction's LP fee for the next active block. Unused capacity moves the fee back
toward its immutable base. Every swap in the same block and direction receives the same fee.

The hook starts with a bounded launch premium, reacts only to executed gross quote flow, and irreversibly settles to
the base LP fee after the configured warmup window. It uses no oracle, keeper, upgrade, pause, wallet identity,
`tx.origin`, mutable fee authority, creator claim, project hook charge, or custom AMM curve.

The hook separately enforces Programmable's mandatory 10 bps claimable volume fee under policy
`programmable-volume-fee-v1@1.1.0`. That charge is denominated in the canonical quote asset and belongs only to the
immutable Programmable owner. LP fees remain separate and belong to LPs.

`SoftLandingLaunch` turns that hook into a complete atomic launch. It CREATE2-deploys a fixed-supply metadata-bound
token, deploys the exact permission-mask `0x20cc` hook, initializes the native-ETH pool at the committed price, locks
almost the full token supply in a one-sided direct PoolManager position, and executes a paid initial buy in one
PoolManager unlock. The launcher owns the position permanently and has no removal, transfer, rescue, sweep, arbitrary
call, or upgrade path. The launch wallet receives only the tokens purchased by its exact native input.

## Quick start

Requirements: Foundry, Node.js 20+, and npm.

```bash
npm ci --ignore-scripts
forge fmt --check
forge build --sizes
forge test -vvv
npm run simulate
```

Read [MECHANISM.md](MECHANISM.md), [SECURITY.md](SECURITY.md), and [EVIDENCE.md](EVIDENCE.md) before evaluating or
deploying the contracts.

## Interactive mechanism lab

The [`demo/`](demo/) MVP visualizes current-block flow, next-block directional fees, empty-block decay, expiry, and
the separate Programmable fee. It is a local simulator, not a deployment or trading interface.

```bash
cd demo
bun install
bun run dev
```

The frontend uses Vite 8, React, Intent UI components, Zustand, viem, and wagmi. Run `bun run test`, `bun run lint`,
and `bun run build` before publishing it.

## Important limits

- The adaptive component has a one-block lag. The immutable initial fee, not adaptive feedback, covers the first
  launch block.
- Soft Landing does not prevent reordering, private bundles, wash flow, or all one-block MEV.
- A trader can pay real execution costs to raise a following block's directional fee.
- Unsupported specified-quote partial fills revert atomically.
- Positive gross quote flow below 1,000 smallest quote units reverts under the current Programmable fee policy.
- The initial position and its LP fees are deliberately permanent. Only 25,789 wei-token of deterministic rounding
  dust remains in the launcher under the specified 1-billion-token launch configuration, also without a withdrawal
  path.
- Production Universal Router, V4Planner, Permit2, Quoter, StateView, pinned-fork, deployment, and routing evidence are
  separate platform-owned gates and are not claimed by the local direct-PoolManager tests.
- This repository is a prototype. It is not audited, approved, deployed, routed, or live.

## License

MIT. The Programmable reference kernel used as the accounting starting point is also MIT-licensed; see the repository
history and [NOTICE.md](NOTICE.md) for provenance.
