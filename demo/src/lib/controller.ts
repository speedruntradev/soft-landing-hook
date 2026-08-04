export const BPS_DENOMINATOR = 10_000n
export const RATE_DENOMINATOR = 1_000_000n
export const PROGRAMMABLE_HUNDREDTHS_OF_BIP = 1_000n

export type Direction = 'buy' | 'sell'

export interface ControllerConfig {
  baseFeePips: number
  initialBuyFeePips: number
  initialSellFeePips: number
  maxFeePips: number
  riseAt2xTargetPips: number
  decayAtZeroPips: number
  maxExcessBps: number
  warmupBlocks: number
  targetQuotePerBlock: bigint
}

export interface BlockTrace {
  block: number
  buyFlow: bigint
  sellFlow: bigint
  appliedBuyFeePips: number
  appliedSellFeePips: number
  nextBuyFeePips: number
  nextSellFeePips: number
  emptyBlocks: number
  expired: boolean
}

export interface ControllerState {
  block: number
  startBlock: number
  buyFlow: bigint
  sellFlow: bigint
  buyFeePips: number
  sellFeePips: number
  programmableFeeRemainder: bigint
  totalProgrammableFees: bigint
  expired: boolean
  history: BlockTrace[]
}

export const DEFAULT_CONFIG: ControllerConfig = {
  baseFeePips: 3_000,
  initialBuyFeePips: 10_000,
  initialSellFeePips: 10_000,
  maxFeePips: 30_000,
  riseAt2xTargetPips: 5_000,
  decayAtZeroPips: 2_500,
  maxExcessBps: 30_000,
  warmupBlocks: 12,
  targetQuotePerBlock: 10n * 10n ** 18n,
}

export function createControllerState(config = DEFAULT_CONFIG): ControllerState {
  return {
    block: 1,
    startBlock: 1,
    buyFlow: 0n,
    sellFlow: 0n,
    buyFeePips: config.initialBuyFeePips,
    sellFeePips: config.initialSellFeePips,
    programmableFeeRemainder: 0n,
    totalProgrammableFees: 0n,
    expired: false,
    history: [],
  }
}

function divRoundingUp(value: bigint, denominator: bigint) {
  if (value === 0n) return 0n
  return (value + denominator - 1n) / denominator
}

export function nextFeePips(
  flow: bigint,
  currentFeePips: number,
  config = DEFAULT_CONFIG,
): number {
  const target = config.targetQuotePerBlock
  if (flow === target) return currentFeePips

  if (flow > target) {
    const excess = flow - target
    const cappedExcess = (target * BigInt(config.maxExcessBps)) / BPS_DENOMINATOR
    const excessBps =
      excess >= cappedExcess
        ? BigInt(config.maxExcessBps)
        : (excess * BPS_DENOMINATOR) / target
    const increase = divRoundingUp(
      excessBps * BigInt(config.riseAt2xTargetPips),
      BPS_DENOMINATOR,
    )
    return Math.min(config.maxFeePips, currentFeePips + Number(increase))
  }

  const slackBps = ((target - flow) * BPS_DENOMINATOR) / target
  const decrease = divRoundingUp(
    slackBps * BigInt(config.decayAtZeroPips),
    BPS_DENOMINATOR,
  )
  return Math.max(config.baseFeePips, currentFeePips - Number(decrease))
}

export function decayEmptyBlocks(
  feePips: number,
  emptyBlocks: number,
  config = DEFAULT_CONFIG,
): number {
  if (emptyBlocks === 0 || feePips === config.baseFeePips) return feePips
  return Math.max(
    config.baseFeePips,
    feePips - emptyBlocks * config.decayAtZeroPips,
  )
}

export function quoteProgrammableFee(grossQuoteAmount: bigint, remainder: bigint) {
  const product = grossQuoteAmount * PROGRAMMABLE_HUNDREDTHS_OF_BIP
  const baseFee = product / RATE_DENOMINATOR
  const combinedRemainder = (product % RATE_DENOMINATOR) + remainder
  return {
    fee: baseFee + combinedRemainder / RATE_DENOMINATOR,
    remainder: combinedRemainder % RATE_DENOMINATOR,
  }
}

export function recordFlow(
  state: ControllerState,
  direction: Direction,
  grossQuoteAmount: bigint,
): ControllerState {
  if (grossQuoteAmount < 0n) throw new Error('Gross quote flow cannot be negative')
  const programmable = quoteProgrammableFee(
    grossQuoteAmount,
    state.programmableFeeRemainder,
  )

  return {
    ...state,
    buyFlow:
      !state.expired && direction === 'buy'
        ? state.buyFlow + grossQuoteAmount
        : state.buyFlow,
    sellFlow:
      !state.expired && direction === 'sell'
        ? state.sellFlow + grossQuoteAmount
        : state.sellFlow,
    programmableFeeRemainder: programmable.remainder,
    totalProgrammableFees: state.totalProgrammableFees + programmable.fee,
  }
}

export function forecastFees(state: ControllerState, config = DEFAULT_CONFIG) {
  if (state.expired) {
    return { buy: config.baseFeePips, sell: config.baseFeePips }
  }
  return {
    buy: nextFeePips(state.buyFlow, state.buyFeePips, config),
    sell: nextFeePips(state.sellFlow, state.sellFeePips, config),
  }
}

export function advanceBlock(
  state: ControllerState,
  emptyBlocks = 0,
  config = DEFAULT_CONFIG,
): ControllerState {
  if (!Number.isInteger(emptyBlocks) || emptyBlocks < 0) {
    throw new Error('Empty block count must be a non-negative integer')
  }

  const nextBlock = state.block + emptyBlocks + 1
  const expires = state.expired || nextBlock >= state.startBlock + config.warmupBlocks
  const forecast = forecastFees(state, config)
  const nextBuyFee = expires
    ? config.baseFeePips
    : decayEmptyBlocks(forecast.buy, emptyBlocks, config)
  const nextSellFee = expires
    ? config.baseFeePips
    : decayEmptyBlocks(forecast.sell, emptyBlocks, config)
  const trace: BlockTrace = {
    block: state.block,
    buyFlow: state.buyFlow,
    sellFlow: state.sellFlow,
    appliedBuyFeePips: state.buyFeePips,
    appliedSellFeePips: state.sellFeePips,
    nextBuyFeePips: nextBuyFee,
    nextSellFeePips: nextSellFee,
    emptyBlocks,
    expired: expires,
  }

  return {
    ...state,
    block: nextBlock,
    buyFlow: 0n,
    sellFlow: 0n,
    buyFeePips: nextBuyFee,
    sellFeePips: nextSellFee,
    expired: expires,
    history: [...state.history, trace].slice(-12),
  }
}

export function pipsToPercent(pips: number) {
  return pips / 10_000
}
