#!/usr/bin/env node

const config = {
  base: 30,
  initial: 100,
  max: 300,
  target: 10,
  riseAt2x: 50,
  decayAtZero: 25,
  maxExcessBps: 30_000,
};

function nextFee(flow, fee) {
  if (flow === config.target) return fee;
  if (flow > config.target) {
    const excessBps = Math.min(
      Math.floor(((flow - config.target) * 10_000) / config.target),
      config.maxExcessBps,
    );
    const increase = Math.ceil((excessBps * config.riseAt2x) / 10_000);
    return Math.min(config.max, fee + increase);
  }
  const slackBps = Math.floor(((config.target - flow) * 10_000) / config.target);
  const decrease = Math.ceil((slackBps * config.decayAtZero) / 10_000);
  return Math.max(config.base, fee - decrease);
}

function simulate(name, blocks, expiresAfter = Number.POSITIVE_INFINITY) {
  let buyFee = config.initial;
  let sellFee = config.initial;
  return blocks.map(([buyFlow, sellFlow], index) => {
    const appliedBuyFee = index >= expiresAfter ? config.base : buyFee;
    const appliedSellFee = index >= expiresAfter ? config.base : sellFee;
    if (index < expiresAfter) {
      buyFee = nextFee(buyFlow, buyFee);
      sellFee = nextFee(sellFlow, sellFee);
    } else {
      buyFee = config.base;
      sellFee = config.base;
    }
    return {
      scenario: name,
      block: index + 1,
      buyFlowEth: buyFlow,
      sellFlowEth: sellFlow,
      appliedBuyFeeBps: appliedBuyFee,
      appliedSellFeeBps: appliedSellFee,
      nextBuyFeeBps: buyFee,
      nextSellFeeBps: sellFee,
    };
  });
}

const traces = [
  ...simulate("calm launch", [[5, 2], [4, 3], [3, 2], [2, 2]]),
  ...simulate("first-block burst then calm", [[40, 0], [3, 1], [2, 1], [1, 1]]),
  ...simulate("sustained buy pressure", [[25, 1], [25, 1], [25, 1], [25, 1]]),
  ...simulate("alternating bursts", [[25, 1], [1, 25], [25, 1], [1, 25]]),
  ...simulate("panic selling", [[2, 30], [1, 35], [1, 25], [1, 15]]),
  ...simulate("paid target grief", [[40, 0], [0, 0], [0, 0], [0, 0]]),
  ...simulate("LP-owned wash flow", [[25, 25], [25, 25], [0, 0], [0, 0]]),
  ...simulate("long inactivity", [[20, 2], [0, 0], [0, 0], [0, 0], [0, 0]]),
  ...simulate("activity before expiry", [[20, 2], [20, 2], [25, 1], [0, 0]], 3),
  ...simulate("first swap after expiry", [[20, 2], [25, 1], [50, 50], [50, 50]], 2),
];

if (process.argv.includes("--csv")) {
  const headers = Object.keys(traces[0]);
  process.stdout.write(`${headers.join(",")}\n`);
  for (const row of traces) process.stdout.write(`${headers.map((header) => row[header]).join(",")}\n`);
} else {
  console.table(traces);
}
