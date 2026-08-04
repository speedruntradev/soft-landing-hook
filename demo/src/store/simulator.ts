import { parseEther } from 'viem'
import { create } from 'zustand'
import {
  advanceBlock,
  createControllerState,
  recordFlow,
  type ControllerState,
  type Direction,
} from '@/lib/controller'
import { SCENARIOS } from '@/lib/scenarios'

interface SimulatorStore {
  controller: ControllerState
  tradeSizeEth: number
  activeScenario: string
  setTradeSize: (value: number) => void
  addTrade: (direction: Direction) => void
  advance: (emptyBlocks?: number) => void
  runScenario: (scenarioId: string) => void
  reset: () => void
}

function eth(amount: number) {
  return parseEther(String(amount))
}

export const useSimulator = create<SimulatorStore>((set, get) => ({
  controller: createControllerState(),
  tradeSizeEth: 5,
  activeScenario: 'custom',
  setTradeSize: (value) => set({ tradeSizeEth: value }),
  addTrade: (direction) => {
    const { controller, tradeSizeEth } = get()
    set({
      controller: recordFlow(controller, direction, eth(tradeSizeEth)),
      activeScenario: 'custom',
    })
  },
  advance: (emptyBlocks = 0) =>
    set(({ controller }) => ({
      controller: advanceBlock(controller, emptyBlocks),
      activeScenario: 'custom',
    })),
  runScenario: (scenarioId) => {
    const scenario = SCENARIOS.find((candidate) => candidate.id === scenarioId)
    if (!scenario) return

    let controller = createControllerState()
    for (const [buyEth, sellEth] of scenario.blocks) {
      controller = recordFlow(controller, 'buy', eth(buyEth))
      controller = recordFlow(controller, 'sell', eth(sellEth))
      controller = advanceBlock(controller)
    }
    set({ controller, activeScenario: scenario.id })
  },
  reset: () => set({ controller: createControllerState(), activeScenario: 'custom' }),
}))
