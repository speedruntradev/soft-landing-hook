import {
  ArrowDownLeft,
  ArrowUpRight,
  Blocks,
  Check,
  ChevronRight,
  CircleDot,
  ExternalLink,
  Gauge,
  GitFork,
  Hourglass,
  RotateCcw,
  ShieldCheck,
  Wallet,
  Waves,
} from 'lucide-react'
import { formatEther } from 'viem'
import {
  useConnect,
  useConnection,
  useConnectors,
  useDisconnect,
} from 'wagmi'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardAction,
  CardContent,
  CardHeader,
} from '@/components/ui/card'
import {
  Slider,
  SliderOutput,
  SliderThumb,
  SliderTrack,
} from '@/components/ui/slider'
import {
  DEFAULT_CONFIG,
  forecastFees,
  pipsToPercent,
  type BlockTrace,
  type Direction,
} from '@/lib/controller'
import { SCENARIOS } from '@/lib/scenarios'
import { useSimulator } from '@/store/simulator'
import './App.css'

const SOURCE_URL = 'https://github.com/speedruntradev/soft-landing-hook'

function feeLabel(pips: number) {
  return `${pipsToPercent(pips).toFixed(2)}%`
}

function flowLabel(value: bigint) {
  const amount = Number(formatEther(value))
  return `${amount.toLocaleString(undefined, { maximumFractionDigits: 2 })} ETH`
}

function compactAddress(address: string) {
  return `${address.slice(0, 6)}…${address.slice(-4)}`
}

function WalletControl() {
  const connection = useConnection()
  const connectors = useConnectors()
  const { mutate: connect, isPending: isConnecting } = useConnect()
  const { mutate: disconnect } = useDisconnect()
  const connector = connectors[0]

  if (connection.status === 'connected') {
    return (
      <Button
        intent="outline"
        className="wallet-button"
        onPress={() => disconnect({ connector: connection.connector })}
      >
        <span className="status-dot" />
        {compactAddress(connection.address)}
      </Button>
    )
  }

  return (
    <Button
      intent="outline"
      className="wallet-button"
      isDisabled={!connector || isConnecting}
      onPress={() => connector && connect({ connector })}
    >
      <Wallet />
      {isConnecting ? 'Opening wallet…' : 'Connect wallet'}
    </Button>
  )
}

interface DirectionPanelProps {
  direction: Direction
  currentFee: number
  nextFee: number
  flow: bigint
  onAdd: () => void
}

function DirectionPanel({
  direction,
  currentFee,
  nextFee,
  flow,
  onAdd,
}: DirectionPanelProps) {
  const isBuy = direction === 'buy'
  const utilization = Number((flow * 100n) / DEFAULT_CONFIG.targetQuotePerBlock)
  const visualUtilization = Math.min(utilization, 100)
  const change = nextFee - currentFee

  return (
    <article className={`direction-panel ${direction}`}>
      <div className="direction-heading">
        <div className="direction-icon">
          {isBuy ? <ArrowUpRight /> : <ArrowDownLeft />}
        </div>
        <div>
          <span className="eyebrow">{isBuy ? 'BUY / QUOTE IN' : 'SELL / QUOTE OUT'}</span>
          <h3>{isBuy ? 'Buy pressure' : 'Sell pressure'}</h3>
        </div>
      </div>

      <div className="fee-readout">
        <div>
          <span>Applied now</span>
          <strong>{feeLabel(currentFee)}</strong>
        </div>
        <ChevronRight />
        <div className="forecast-value">
          <span>Next block</span>
          <strong>{feeLabel(nextFee)}</strong>
          <small className={change > 0 ? 'rising' : change < 0 ? 'falling' : ''}>
            {change === 0 ? 'unchanged' : `${change > 0 ? '+' : ''}${change / 100} bps`}
          </small>
        </div>
      </div>

      <div className="flow-row">
        <span>Gross quote flow</span>
        <span>{flowLabel(flow)} / 10 ETH target</span>
      </div>
      <div className="flow-track" aria-label={`${utilization}% of target flow`}>
        <span style={{ width: `${visualUtilization}%` }} />
        <i className="target-tick" />
      </div>
      <div className="panel-footer">
        <span>{utilization}% target utilization</span>
        <Button intent="outline" size="sm" onPress={onAdd}>
          Add {isBuy ? 'buy' : 'sell'}
        </Button>
      </div>
    </article>
  )
}

function FeeChart({ history, currentBuy, currentSell }: {
  history: BlockTrace[]
  currentBuy: number
  currentSell: number
}) {
  const points = [
    ...history.map((trace) => ({
      block: trace.block,
      buy: trace.appliedBuyFeePips,
      sell: trace.appliedSellFeePips,
    })),
    {
      block: history.length ? history.at(-1)!.block + history.at(-1)!.emptyBlocks + 1 : 1,
      buy: currentBuy,
      sell: currentSell,
    },
  ].slice(-9)
  const width = 720
  const height = 210
  const paddingX = 28
  const paddingY = 20
  const maxFee = DEFAULT_CONFIG.maxFeePips
  const xFor = (index: number) =>
    paddingX + (index * (width - paddingX * 2)) / Math.max(points.length - 1, 1)
  const yFor = (fee: number) =>
    paddingY + ((maxFee - fee) * (height - paddingY * 2)) / maxFee
  const buyPoints = points.map((point, index) => `${xFor(index)},${yFor(point.buy)}`).join(' ')
  const sellPoints = points.map((point, index) => `${xFor(index)},${yFor(point.sell)}`).join(' ')

  return (
    <div className="chart-wrap">
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Directional LP fees by block">
        {[0.5, 1, 2, 3].map((percent) => {
          const y = yFor(percent * 10_000)
          return (
            <g key={percent}>
              <line x1={paddingX} x2={width - paddingX} y1={y} y2={y} className="chart-grid" />
              <text x={paddingX} y={y - 6} className="chart-label">{percent}%</text>
            </g>
          )
        })}
        <polyline points={buyPoints} className="chart-line buy-line" />
        <polyline points={sellPoints} className="chart-line sell-line" />
        {points.map((point, index) => (
          <g key={`${point.block}-${index}`}>
            <circle cx={xFor(index)} cy={yFor(point.buy)} r="4" className="chart-dot buy-dot" />
            <circle cx={xFor(index)} cy={yFor(point.sell)} r="4" className="chart-dot sell-dot" />
            <text x={xFor(index)} y={height - 1} textAnchor="middle" className="chart-block">
              B{point.block}
            </text>
          </g>
        ))}
      </svg>
      <div className="chart-legend">
        <span><i className="legend-dot buy-dot" /> Buy fee</span>
        <span><i className="legend-dot sell-dot" /> Sell fee</span>
      </div>
    </div>
  )
}

function App() {
  const controller = useSimulator((state) => state.controller)
  const tradeSize = useSimulator((state) => state.tradeSizeEth)
  const activeScenario = useSimulator((state) => state.activeScenario)
  const setTradeSize = useSimulator((state) => state.setTradeSize)
  const addTrade = useSimulator((state) => state.addTrade)
  const advance = useSimulator((state) => state.advance)
  const runScenario = useSimulator((state) => state.runScenario)
  const reset = useSimulator((state) => state.reset)
  const forecast = forecastFees(controller)
  const endBlock = controller.startBlock + DEFAULT_CONFIG.warmupBlocks
  const blocksRemaining = Math.max(endBlock - controller.block, 0)
  const accruedFee = Number(formatEther(controller.totalProgrammableFees))

  return (
    <div className="app-shell">
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Soft Landing home">
          <span className="brand-mark"><Waves /></span>
          <span>SOFT<span>LANDING</span></span>
        </a>
        <nav className="header-actions" aria-label="Project links">
          <a className="source-link" href={SOURCE_URL} target="_blank" rel="noreferrer">
            <GitFork /> <span>Source</span>
          </a>
          <WalletControl />
        </nav>
      </header>

      <main id="top">
        <section className="hero">
          <div className="hero-glow hero-glow-one" />
          <div className="hero-glow hero-glow-two" />
          <Badge intent="success" className="hero-badge">
            <CircleDot /> LOCAL MECHANISM LAB
          </Badge>
          <h1>Let launch pressure rise.<br /><em>Then land softly.</em></h1>
          <p>
            A block-stable, directional congestion controller for Uniswap v4 launches.
            Flow in this block shapes the fee in the next—never its own.
          </p>
          <div className="hero-facts">
            <span><Check /> Same-block stable</span>
            <span><Check /> Buy / sell independent</span>
            <span><Check /> Expires to base</span>
          </div>
        </section>

        <section className="rule-strip" aria-label="Mechanism sequence">
          <div><span>01</span><strong>Hold</strong><small>Current block fee stays fixed</small></div>
          <ChevronRight />
          <div><span>02</span><strong>Measure</strong><small>Executed gross quote flow</small></div>
          <ChevronRight />
          <div><span>03</span><strong>Adapt</strong><small>Next block, per direction</small></div>
        </section>

        <section className="demo-section" aria-labelledby="lab-title">
          <div className="section-heading">
            <div>
              <Badge intent={controller.expired ? 'secondary' : 'success'}>
                {controller.expired ? 'CONTROLLER EXPIRED' : 'CONTROLLER ACTIVE'}
              </Badge>
              <h2 id="lab-title">Block pressure lab</h2>
              <p>Build flow inside the current block, then roll it forward.</p>
            </div>
            <div className="block-status">
              <span><Blocks /> SIMULATED BLOCK</span>
              <strong>#{controller.block}</strong>
              <small>{controller.expired ? 'Fixed at base' : `${blocksRemaining} active blocks left`}</small>
            </div>
          </div>

          <div className="lab-grid">
            <Card className="pressure-card">
              <CardHeader title="Directional pressure" description="One fee per side, stable for the whole block.">
                <CardAction>
                  <Badge intent="outline">Target 10 ETH / block</Badge>
                </CardAction>
              </CardHeader>
              <CardContent className="direction-grid">
                <DirectionPanel
                  direction="buy"
                  currentFee={controller.buyFeePips}
                  nextFee={forecast.buy}
                  flow={controller.buyFlow}
                  onAdd={() => addTrade('buy')}
                />
                <DirectionPanel
                  direction="sell"
                  currentFee={controller.sellFeePips}
                  nextFee={forecast.sell}
                  flow={controller.sellFlow}
                  onAdd={() => addTrade('sell')}
                />
              </CardContent>
            </Card>

            <Card className="control-card">
              <CardHeader title="Shape this block" description="Every click simulates executed gross quote flow." />
              <CardContent>
                <div className="trade-size-label">
                  <span>Trade size</span>
                  <strong>{tradeSize} ETH</strong>
                </div>
                <Slider
                  aria-label="Simulated trade size in ETH"
                  minValue={1}
                  maxValue={40}
                  step={1}
                  value={tradeSize}
                  onChange={(value) => setTradeSize(Array.isArray(value) ? value[0] : value)}
                >
                  <SliderOutput className="sr-only" />
                  <SliderTrack className="trade-slider-track">
                    {({ state }) => (
                      <>
                        <span className="trade-slider-fill" style={{ width: `${state.getThumbPercent(0) * 100}%` }} />
                        <SliderThumb className="trade-slider-thumb" />
                      </>
                    )}
                  </SliderTrack>
                </Slider>
                <div className="slider-range"><span>1 ETH</span><span>40 ETH</span></div>

                <div className="trade-buttons">
                  <Button intent="success" size="lg" onPress={() => addTrade('buy')}>
                    <ArrowUpRight /> Add buy
                  </Button>
                  <Button intent="warning" size="lg" onPress={() => addTrade('sell')}>
                    <ArrowDownLeft /> Add sell
                  </Button>
                </div>

                <div className="advance-box">
                  <div>
                    <strong>Commit the completed block</strong>
                    <span>Forecast becomes the next applied fee.</span>
                  </div>
                  <Button className="advance-button" onPress={() => advance()}>
                    Advance block <ChevronRight />
                  </Button>
                </div>
                <button className="skip-link" type="button" onClick={() => advance(2)}>
                  <Hourglass /> Skip 2 empty blocks to test decay
                </button>
              </CardContent>
            </Card>
          </div>

          <div className="scenario-row">
            <div className="scenario-intro">
              <span className="eyebrow">REPLAY TRACES</span>
              <strong>Stress the launch</strong>
              <button type="button" onClick={reset}><RotateCcw /> Reset</button>
            </div>
            {SCENARIOS.map((scenario) => (
              <button
                className={`scenario-button ${activeScenario === scenario.id ? 'active' : ''}`}
                type="button"
                key={scenario.id}
                onClick={() => runScenario(scenario.id)}
              >
                <span>{scenario.label}</span>
                <small>{scenario.description}</small>
              </button>
            ))}
          </div>

          <div className="insight-grid">
            <Card className="chart-card">
              <CardHeader title="Fee trajectory" description="Applied LP fee—not a price or swap quote.">
                <CardAction><Gauge /></CardAction>
              </CardHeader>
              <CardContent>
                <FeeChart
                  history={controller.history}
                  currentBuy={controller.buyFeePips}
                  currentSell={controller.sellFeePips}
                />
              </CardContent>
            </Card>

            <Card className="economics-card">
              <CardHeader title="Launch economics" description="Exact model constants from the hook." />
              <CardContent>
                <div className="economics-stat featured">
                  <span>Programmable fee accrued</span>
                  <strong>{accruedFee.toFixed(4)} ETH</strong>
                  <small>10 bps on gross quote volume · separate from LP fee</small>
                </div>
                <dl className="constants-grid">
                  <div><dt>Base</dt><dd>30 bps</dd></div>
                  <div><dt>Initial</dt><dd>100 bps</dd></div>
                  <div><dt>Maximum</dt><dd>300 bps</dd></div>
                  <div><dt>Target</dt><dd>10 ETH</dd></div>
                </dl>
                <div className="safety-note">
                  <ShieldCheck />
                  <p><strong>No selective blocking.</strong> The controller prices sustained congestion and permanently returns to base after expiry.</p>
                </div>
              </CardContent>
            </Card>
          </div>

          <Card className="trace-card">
            <CardHeader title="Completed blocks" description="The latest controller transitions in this local run." />
            <CardContent>
              {controller.history.length === 0 ? (
                <div className="empty-trace"><Blocks /><span>Advance a block or load a trace to populate the ledger.</span></div>
              ) : (
                <div className="trace-table-wrap">
                  <table>
                    <thead><tr><th>Block</th><th>Buy flow</th><th>Sell flow</th><th>Applied buy</th><th>Applied sell</th><th>Next buy</th><th>Next sell</th></tr></thead>
                    <tbody>
                      {[...controller.history].reverse().slice(0, 6).map((trace) => (
                        <tr key={`${trace.block}-${trace.emptyBlocks}`}>
                          <td>#{trace.block}{trace.emptyBlocks > 0 && <small> +{trace.emptyBlocks} empty</small>}</td>
                          <td>{flowLabel(trace.buyFlow)}</td>
                          <td>{flowLabel(trace.sellFlow)}</td>
                          <td>{feeLabel(trace.appliedBuyFeePips)}</td>
                          <td>{feeLabel(trace.appliedSellFeePips)}</td>
                          <td className="buy-text">{feeLabel(trace.nextBuyFeePips)}</td>
                          <td className="sell-text">{feeLabel(trace.nextSellFeePips)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </CardContent>
          </Card>
        </section>

        <section className="truth-banner">
          <div className="truth-icon"><ShieldCheck /></div>
          <div>
            <span className="eyebrow">DEMO BOUNDARY</span>
            <h2>A simulator with receipts, not a fake deployment.</h2>
            <p>This MVP performs no swaps, contract writes, live quotes, or chain reads. Wallet connection is optional identity plumbing via wagmi; the engine is a typed local port of <code>FlowFeeMath.sol</code>.</p>
          </div>
          <a href={`${SOURCE_URL}/blob/main/MECHANISM.md`} target="_blank" rel="noreferrer">
            Read mechanism <ExternalLink />
          </a>
        </section>
      </main>

      <footer>
        <a className="brand" href="#top"><span className="brand-mark"><Waves /></span><span>SOFT<span>LANDING</span></span></a>
        <p>Interactive local model · Not deployed · Not a trading interface</p>
        <a href={SOURCE_URL} target="_blank" rel="noreferrer"><GitFork /> speedruntradev</a>
      </footer>
    </div>
  )
}

export default App
