# Implementation evidence

Evidence must be regenerated for the exact commit being reviewed. A passing local command is not an audit, maintainer
approval, deployment receipt, routing decision, or proof of live fee collection.

## Deterministic build profile

```text
Solidity: 0.8.26
EVM: Cancun
optimizer: enabled, 200 runs
via IR: enabled
bytecode metadata hash: none
FFI: disabled
dependencies: exact versions and registry integrities in package.json and package-lock.json
```

## Commands

```bash
npm ci --ignore-scripts --no-audit --no-fund
forge fmt --check
forge build --sizes
forge test -vvv
forge lint src test --severity high --severity med --severity low
forge test --gas-report
node simulations/launch-traces.mjs
```

## Covered properties

- Pure controller examples, bounds, monotonicity, utilization rounding, and skipped-block equivalence
- Stateful constant-time decay versus explicit empty-block iteration
- Real PoolManager execution for all four swap quadrants with native quote
- Real PoolManager execution for all four swap quadrants with ERC-20 quote as currency1
- First-swap start, directional next-block update, same-block stability, long gaps, and permanent expiry
- Dynamic LP-fee override flag and exact hook permission mask
- Executed gross quote accounting, specified-quote partial-fill rollback, and quote-unspecified executed deltas
- Minimum quote quantum, exact-output gross-up, cumulative rounding, claim persistence, and fragmentation resistance
- Immutable owner-only claim with per-claim destination and callback/cross-pool authentication
- Deterministic adversarial traces for calm, burst, sustained, alternating, panic, grief, LP wash, inactivity, and expiry

## Known incomplete evidence

- Build-info normalization: Foundry 1.7.1 records only `0.8.26` in `solcLongVersion` when `--use` receives a local
  compiler path. `script/normalize-build-info.mjs` queries the executed binary's `--version`, requires the matching
  short version, and fills the canonical `0.8.26+commit.8a97fa7a` envelope field without changing compiler input or
  output.

- Forge lint: run locally; truncating casts use checked `SafeCast`; remaining diagnostics are non-security style notes
- Slither: unavailable in the local toolchain; pending isolated CI or reviewer run
- Mainnet fork: pending
- Router parity beyond the core test router: pending
- Echidna/Manticore: not run
- Independent review/audit: not performed
- Deployment/runtime/source verification: not applicable; not deployed
