export interface Scenario {
  id: string
  label: string
  description: string
  blocks: readonly (readonly [buyEth: number, sellEth: number])[]
}

export const SCENARIOS: readonly Scenario[] = [
  {
    id: 'calm',
    label: 'Calm launch',
    description: 'Both directions cool toward base.',
    blocks: [
      [5, 2],
      [4, 3],
      [3, 2],
      [2, 2],
    ],
  },
  {
    id: 'burst',
    label: 'Burst → calm',
    description: 'A first-block spike fades over time.',
    blocks: [
      [40, 0],
      [3, 1],
      [2, 1],
      [1, 1],
    ],
  },
  {
    id: 'alternating',
    label: 'Alternating pressure',
    description: 'Independent fees follow each side.',
    blocks: [
      [25, 1],
      [1, 25],
      [25, 1],
      [1, 25],
    ],
  },
  {
    id: 'panic',
    label: 'Panic selling',
    description: 'Sell congestion rises without taxing buys.',
    blocks: [
      [2, 30],
      [1, 35],
      [1, 25],
      [1, 15],
    ],
  },
] as const
