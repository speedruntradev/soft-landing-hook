# Soft Landing mechanism lab

An interactive local MVP for the Soft Landing Uniswap v4 hook. It ports the directional controller and Programmable
fee arithmetic into typed, deterministic TypeScript so reviewers can explore the block-to-block behavior without a
deployment.

## Run with Bun

```bash
cd demo
bun install
bun run dev
```

Quality checks:

```bash
bun run test
bun run lint
bun run build
```

If Bun is not on your shell path, use `/Users/sprt/.bun/bin/bun` locally or use Node/npm as a fallback.

## What it demonstrates

- the LP fee is stable for every swap in the current block;
- completed gross quote flow independently changes the next buy and sell fees;
- skipped empty blocks decay both directions toward the base fee;
- the controller permanently expires to its base fee; and
- the separate mandatory 10 bps Programmable fee uses lifetime remainder accounting.

The wallet button uses wagmi with an injected connector. Connecting is optional and does not initiate a transaction.

## Boundary

This is a local mechanism simulator. It does not perform swaps, write contracts, read live chain state, return executable
quotes, or claim that the hook is deployed. The reviewed Solidity source remains the authority for production behavior.
