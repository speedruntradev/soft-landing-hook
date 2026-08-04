import { describe, expect, it } from 'vitest'
import {
  DEFAULT_CONFIG,
  advanceBlock,
  createControllerState,
  decayEmptyBlocks,
  forecastFees,
  nextFeePips,
  quoteProgrammableFee,
  recordFlow,
} from './controller'

const eth = (amount: number) => BigInt(amount) * 10n ** 18n

describe('Soft Landing controller model', () => {
  it('keeps the applied fee stable while swaps accumulate in one block', () => {
    const initial = createControllerState()
    const afterBuy = recordFlow(initial, 'buy', eth(25))
    const afterAnotherBuy = recordFlow(afterBuy, 'buy', eth(5))

    expect(afterAnotherBuy.buyFeePips).toBe(initial.buyFeePips)
    expect(afterAnotherBuy.buyFlow).toBe(eth(30))
    expect(forecastFees(afterAnotherBuy).buy).toBe(20_000)
  })

  it('applies completed directional flow only to the next block', () => {
    let state = createControllerState()
    state = recordFlow(state, 'buy', eth(25))
    state = recordFlow(state, 'sell', eth(2))
    state = advanceBlock(state)

    expect(state.buyFeePips).toBe(17_500)
    expect(state.sellFeePips).toBe(8_000)
    expect(state.buyFlow).toBe(0n)
    expect(state.sellFlow).toBe(0n)
  })

  it('matches target, zero-flow, and cap behavior from FlowFeeMath', () => {
    expect(nextFeePips(eth(10), 10_000)).toBe(10_000)
    expect(nextFeePips(0n, 10_000)).toBe(7_500)
    expect(nextFeePips(eth(110), 20_000)).toBe(DEFAULT_CONFIG.maxFeePips)
  })

  it('decays skipped empty blocks in constant-time semantics', () => {
    expect(decayEmptyBlocks(17_500, 3)).toBe(10_000)
    expect(decayEmptyBlocks(5_000, 20)).toBe(DEFAULT_CONFIG.baseFeePips)
  })

  it('expires irreversibly at the exclusive end block', () => {
    let state = createControllerState()
    state = advanceBlock(state, DEFAULT_CONFIG.warmupBlocks - 1)
    expect(state.expired).toBe(true)
    expect(state.buyFeePips).toBe(DEFAULT_CONFIG.baseFeePips)

    state = recordFlow(state, 'buy', eth(50))
    state = advanceBlock(state)
    expect(state.buyFeePips).toBe(DEFAULT_CONFIG.baseFeePips)
    expect(state.buyFlow).toBe(0n)
  })

  it('preserves the lifetime remainder for the mandatory 10 bps fee', () => {
    const first = quoteProgrammableFee(1_001n, 0n)
    const second = quoteProgrammableFee(1_001n, first.remainder)

    expect(first.fee).toBe(1n)
    expect(first.remainder).toBe(1_000n)
    expect(second.fee).toBe(1n)
    expect(second.remainder).toBe(2_000n)
  })
})
