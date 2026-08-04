# Soft Landing

**Block-stable directional congestion pricing for the unstable launch phase of a Uniswap v4 pool.**

Soft Landing gives buy-side and sell-side quote flow independent throughput targets. A completed block above its
directional target raises only that direction's LP fee for the next active block. Unused capacity moves the fee back
toward its immutable base. Every swap in the same block and direction receives the same fee.

The hook starts with a bounded launch premium, reacts only to executed gross quote flow, and irreversibly settles to
the base LP fee after the configured warmup window. It uses no oracle, keeper, upgrade, pause, wallet identity,
`tx.origin`, mutable fee authority, creator claim, project hook charge, or custom AMM curve.

The hook separately enforces Programmable's mandatory 10 bps claimable volume fee under policy
`programmable-volume-fee-v1@1.0.0`. That charge is denominated in the canonical quote asset and belongs only to the
immutable Programmable owner. LP fees remain separate and belong to LPs.

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

## Important limits

- The adaptive component has a one-block lag. The immutable initial fee, not adaptive feedback, covers the first
  launch block.
- Soft Landing does not prevent reordering, private bundles, wash flow, or all one-block MEV.
- A trader can pay real execution costs to raise a following block's directional fee.
- Unsupported specified-quote partial fills revert atomically.
- Positive gross quote flow below 1,000 smallest quote units reverts under the current Programmable fee policy.
- This repository is a prototype. It is not audited, approved, deployed, routed, or live.

## License

MIT. The Programmable reference kernel used as the accounting starting point is also MIT-licensed; see the repository
history and [NOTICE.md](NOTICE.md) for provenance.
