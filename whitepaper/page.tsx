import type { Metadata } from 'next'
import Link from 'next/link'
import {
    BookOpen,
    AlertTriangle,
    Layers,
    Dna,
    Vault,
    ShieldCheck,
    Coins,
    Eye,
    Map,
    Scale,
    FileWarning,
    ArrowRight,
    ExternalLink,
    ChevronRight,
    Users,
} from 'lucide-react'
import LegalDisclaimer from '@/components/LegalDisclaimer'

export const metadata: Metadata = {
    title: 'Whitepaper | Zentory Labs',
    description:
        'Zentory Labs whitepaper — a non-custodial evolutionary alpha network for liquid crypto. Genetic programming, on-chain vaults, risk-bounded execution.',
    keywords: [
        'Zentory Labs',
        'whitepaper',
        'genetic programming',
        'crypto alpha',
        'DeFi vaults',
        'evolutionary trading',
        'tokenomics',
        'layer 1',
    ],
    openGraph: {
        url: '/wpvf',
        title: 'Whitepaper | Zentory Labs',
        description:
            'Zentory Labs whitepaper — evolutionary alpha engine for crypto. Genetic programming, benchmark-denominated vaults, risk-bounded execution.',
    },
}

/* ── Table of Contents data ────────────────────── */
const TOC = [
    { id: 'abstract', label: 'Abstract', icon: BookOpen },
    { id: 'problem', label: 'Problem Statement', icon: AlertTriangle },
    { id: 'architecture', label: 'Protocol Architecture', icon: Layers },
    { id: 'team', label: 'The Team', icon: Users },
    { id: 'risk', label: 'Risk Controls & Verification', icon: ShieldCheck },
    { id: 'tokenomics', label: 'Tokenomics Overview', icon: Coins },
    { id: 'roadmap', label: 'Roadmap', icon: Map },
    { id: 'regulatory', label: 'Regulatory', icon: Scale },
    { id: 'disclaimer', label: 'Disclaimer', icon: FileWarning },
]

/* ── Reusable components ───────────────────────── */
function SectionHeading({
    id,
    icon: Icon,
    number,
    title,
    variant = 'blue',
}: {
    id: string
    icon: React.ElementType
    number: string
    title: string
    variant?: 'blue' | 'amber'
}) {
    const isAmber = variant === 'amber'
    const bgClass = isAmber ? 'bg-amber-500/10' : 'bg-[#0d80fa]/10'
    const textClass = isAmber ? 'text-amber-500' : 'text-[#0d80fa]'
    const labelClass = isAmber ? 'text-amber-500' : 'text-[#0d80fa]'

    return (
        <div id={id} className="scroll-mt-32 flex items-center gap-4 mb-8">
            <div className={`w-12 h-12 rounded-xl ${bgClass} flex items-center justify-center flex-shrink-0`}>
                <Icon className={`w-6 h-6 ${textClass}`} />
            </div>
            <div>
                <span className={`text-xs ${labelClass} font-semibold uppercase tracking-widest`}>
                    Section {number}
                </span>
                <h2 className="text-2xl md:text-3xl font-bold text-white tracking-tight">{title}</h2>
            </div>
        </div>
    )
}

function InfoCard({ title, children }: { title: string; children: React.ReactNode }) {
    return (
        <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-8">
            <h4 className="text-lg font-semibold text-white mb-4">{title}</h4>
            <div className="text-white/70 text-sm leading-relaxed space-y-3">{children}</div>
        </div>
    )
}

/* ── Page ───────────────────────────────────────── */
export default function WhitepaperPage() {
    return (
        <div className="min-h-screen bg-[#05070c] text-[#e6e2de]">
            {/* Ambient glow effects */}
            <div className="fixed inset-0 pointer-events-none overflow-hidden">
                <div className="absolute top-0 left-1/4 w-96 h-96 bg-[#0d80fa]/5 rounded-full blur-3xl" />
                <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-amber-500/5 rounded-full blur-3xl" />
            </div>

            {/* Hero */}
            <section className="relative py-20 md:py-28 overflow-hidden">
                <div className="absolute inset-0 bg-gradient-to-b from-[#0d80fa]/10 via-transparent to-transparent" />
                <div className="max-w-4xl mx-auto px-6 relative z-10 text-center">
                    <span className="inline-block px-4 py-2 bg-amber-500/20 text-amber-500 rounded-full text-xs font-semibold uppercase tracking-widest mb-6">
                        Whitepaper v1.0 — March 2026
                    </span>
                    <h1 className="text-4xl md:text-6xl font-bold tracking-tight mb-6">
                        Zentory <span className="text-[#0d80fa]">Protocol</span>
                    </h1>
                    <p className="text-xl text-white/70 font-light max-w-2xl mx-auto leading-relaxed mb-8">
                        A non-custodial evolutionary alpha network for liquid crypto. Genetic programming, benchmark-denominated
                        vaults, and risk-bounded execution — verified on-chain.
                    </p>
                    <div className="flex flex-col sm:flex-row gap-4 justify-center">
                        <Link
                            href="/models/pitch-deck"
                            className="inline-flex items-center justify-center gap-2 px-6 py-3 rounded-xl bg-gradient-to-r from-[#0d80fa] to-[#3b82f6] text-white font-semibold shadow-lg shadow-blue-500/25 transition-all duration-300 hover:scale-[1.02] hover:shadow-blue-500/40"
                        >
                            View Pitch Deck
                            <ArrowRight className="w-4 h-4" />
                        </Link>
                        <Link
                            href="/tokenomics"
                            className="inline-flex items-center justify-center gap-2 px-6 py-3 rounded-xl border border-white/20 text-white/80 hover:text-white hover:border-white/40 font-medium transition-all duration-300"
                        >
                            Tokenomics
                            <ExternalLink className="w-4 h-4" />
                        </Link>
                    </div>
                </div>
            </section>

            {/* Layout: TOC sidebar + content */}
            <div className="max-w-7xl mx-auto px-6 pb-20 flex gap-12">
                {/* Sticky TOC — desktop with glass effect */}
                <aside className="hidden xl:block w-64 flex-shrink-0">
                    <nav className="sticky top-20 w-64 p-6 glass border-r border-white/[0.08] rounded-2xl space-y-1">
                        <p className="text-xs text-white/40 uppercase tracking-widest font-semibold mb-4 px-3">
                            Contents
                        </p>
                        {TOC.map((item) => {
                            const Icon = item.icon
                            return (
                                <a
                                    key={item.id}
                                    href={`#${item.id}`}
                                    className="flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-white/60 hover:text-white hover:bg-white/5 transition-colors group"
                                >
                                    <Icon className="w-4 h-4 text-white/30 group-hover:text-[#0d80fa] transition-colors" />
                                    {item.label}
                                </a>
                            )
                        })}
                    </nav>
                </aside>

                {/* Mobile TOC */}
                <div className="xl:hidden fixed bottom-6 right-6 z-40">
                    <details className="group">
                        <summary className="cursor-pointer w-12 h-12 rounded-full bg-gradient-to-r from-[#0d80fa] to-[#3b82f6] flex items-center justify-center shadow-lg shadow-blue-500/25 hover:scale-105 transition-transform list-none">
                            <BookOpen className="w-5 h-5 text-white" />
                        </summary>
                        <div className="absolute bottom-14 right-0 w-56 glass border border-white/[0.1] rounded-xl p-3 shadow-2xl max-h-[60vh] overflow-y-auto">
                            <p className="text-xs text-white/40 uppercase tracking-widest font-semibold mb-2 px-2">
                                Contents
                            </p>
                            {TOC.map((item) => (
                                <a
                                    key={item.id}
                                    href={`#${item.id}`}
                                    className="block px-3 py-2 text-sm text-white/60 hover:text-white hover:bg-white/5 rounded-lg transition-colors"
                                >
                                    {item.label}
                                </a>
                            ))}
                        </div>
                    </details>
                </div>

                {/* Main content */}
                <article className="flex-1 max-w-4xl space-y-20">
                    {/* ─── 1  Abstract ──────────────────────────── */}
                    <section>
                        <SectionHeading id="abstract" icon={BookOpen} number="01" title="Abstract" />
                        <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6 md:p-8">
                            <p className="text-white/80 leading-relaxed text-lg font-light">
                                Zentory is a non-custodial, tokenized strategy network for liquid cryptocurrency markets. The protocol
                                combines genetic programming research, on-chain vaults adhering to the ERC-4626 standard, and
                                risk-bounded derivatives execution to allocate capital across verifiable alpha models. Users stake the
                                ZENT token to access per-asset strategy vaults — zBTC, zETH, zSOL, zXRP — each independently engineered
                                to seek risk-adjusted outperformance versus passive holding of the underlying asset. Performance is
                                measured as benchmark-denominated alpha, tracked on-chain, and fees are only charged on positive spread
                                above the HODL baseline.
                            </p>
                        </div>
                    </section>

                    {/* ─── 2  Problem Statement ─────────────────── */}
                    <section>
                        <SectionHeading id="problem" icon={AlertTriangle} number="02" title="Problem Statement" />
                        <div className="space-y-8 text-white/70 leading-relaxed">
                            {/* Market Gaps */}
                            <div className="grid md:grid-cols-3 gap-6">
                                <InfoCard title="Unsustainable DeFi Yields">
                                    <p>
                                        Over 80% of DeFi protocols rely on inflationary token emissions rather than genuine economic
                                        activity. When emission schedules decay, yields collapse and early adopters profit at the expense of
                                        late entrants.
                                    </p>
                                </InfoCard>
                                <InfoCard title="Alpha Is Inaccessible">
                                    <p>
                                        Sophisticated α-generation strategies — long/short, basis trading, statistical arbitrage — remain
                                        locked inside institutional hedge funds with $1M+ minimums and accredited investor requirements.
                                    </p>
                                </InfoCard>
                                <InfoCard title="Opacity and Trust">
                                    <p>
                                        Most &ldquo;AI trading tokens&rdquo; operate as opaque black boxes. Users cannot verify whether
                                        returns come from skill, hidden leverage, treasury subsidies, or selective reporting.
                                    </p>
                                </InfoCard>
                            </div>

                            {/* Zentory Solution */}
                            <div className="border-t border-white/10 pt-8">
                                <h3 className="text-xl font-semibold text-white mb-4">The Zentory Solution</h3>
                                <p className="mb-6">
                                    Zentory addresses these gaps by combining three innovations into a single protocol:
                                </p>
                                <div className="grid md:grid-cols-3 gap-6">
                                    <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6 text-center">
                                        <div className="w-14 h-14 rounded-full bg-[#0d80fa]/10 flex items-center justify-center mx-auto mb-4">
                                            <Dna className="w-7 h-7 text-[#0d80fa]" />
                                        </div>
                                        <h4 className="text-white font-semibold mb-2">Evolutionary Alpha Engine</h4>
                                        <p className="text-sm text-white/60">
                                            Genetic programming continuously evolves, tests, and selects trading strategies — eliminating human
                                            bias and adapting to market regime changes.
                                        </p>
                                    </div>
                                    <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6 text-center">
                                        <div className="w-14 h-14 rounded-full bg-amber-500/10 flex items-center justify-center mx-auto mb-4">
                                            <Vault className="w-7 h-7 text-amber-500" />
                                        </div>
                                        <h4 className="text-white font-semibold mb-2">Benchmark-Denominated Vaults</h4>
                                        <p className="text-sm text-white/60">
                                            Per-asset vaults (zBTC, zETH, zSOL, zXRP) that measure and report alpha as &ldquo;additional asset
                                            above holding&rdquo; — not vague USD profit claims.
                                        </p>
                                    </div>
                                    <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6 text-center">
                                        <div className="w-14 h-14 rounded-full bg-[#0d80fa]/10 flex items-center justify-center mx-auto mb-4">
                                            <ShieldCheck className="w-7 h-7 text-[#0d80fa]" />
                                        </div>
                                        <h4 className="text-white font-semibold mb-2">Hard-Coded Risk Rails</h4>
                                        <p className="text-sm text-white/60">
                                            Immutable leverage caps, circuit breakers, and drawdown limits enforced at the smart-contract level —
                                            &ldquo;won&apos;t blow up&rdquo; as a product feature.
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </section>

                    {/* ─── 3  Protocol Architecture ──────────────── */}
                    <section>
                        <SectionHeading id="architecture" icon={Layers} number="03" title="Protocol Architecture" />
                        <div className="space-y-8 text-white/70 leading-relaxed">
                            <p>
                                The Zentory protocol is structured in three integrated layers. Each layer has distinct responsibilities,
                                and a failure in one does not cascade to others.
                            </p>

                            {/* Layer 1: Alpha Vaults */}
                            <div className="rounded-2xl border border-[#0d80fa]/30 bg-[#0d80fa]/5 backdrop-blur-xl p-6">
                                <div className="flex items-center gap-3 mb-4">
                                    <span className="px-2 py-1 bg-gradient-to-r from-[#0d80fa] to-[#3b82f6] text-white text-xs font-bold rounded">LAYER 1</span>
                                    <h4 className="text-white font-semibold text-lg">Alpha Vaults</h4>
                                </div>
                                <p className="text-sm text-white/60 mb-4">
                                    Each Zentory vault is a self-contained strategy product, denominated in its benchmark asset
                                    and built on the ERC-4626 tokenised vault standard. ERC-4626-compliant vaults (zBTC, zETH, zSOL,
                                    zXRP) hold deposited assets, issue benchmark-denominated shares, and enforce risk parameters.
                                </p>

                                {/* Vault table */}
                                <div className="overflow-x-auto mb-4">
                                    <table className="w-full text-sm">
                                        <thead>
                                            <tr className="border-b border-white/10">
                                                <th className="text-left py-2 px-3 text-white/40 uppercase tracking-wider text-xs font-semibold">Vault</th>
                                                <th className="text-left py-2 px-3 text-white/40 uppercase tracking-wider text-xs font-semibold">Deposits</th>
                                                <th className="text-left py-2 px-3 text-white/40 uppercase tracking-wider text-xs font-semibold">Benchmark</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-white/5">
                                            <tr className="hover:bg-white/5"><td className="py-2 px-3 text-white font-medium">zBTC</td><td className="py-2 px-3">WBTC / BTC</td><td className="py-2 px-3">BTC HODL</td></tr>
                                            <tr className="hover:bg-white/5"><td className="py-2 px-3 text-white font-medium">zETH</td><td className="py-2 px-3">WETH / ETH</td><td className="py-2 px-3">ETH HODL</td></tr>
                                            <tr className="hover:bg-white/5"><td className="py-2 px-3 text-white font-medium">zSOL</td><td className="py-2 px-3">SOL</td><td className="py-2 px-3">SOL HODL</td></tr>
                                            <tr className="hover:bg-white/5"><td className="py-2 px-3 text-white font-medium">zXRP</td><td className="py-2 px-3">XRP</td><td className="py-2 px-3">XRP HODL</td></tr>
                                        </tbody>
                                    </table>
                                </div>

                                {/* Alpha Vault Details Grid */}
                                <div className="grid md:grid-cols-2 gap-4">
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">Benchmark-Denominated Returns</h5>
                                        <p className="text-xs text-white/60">
                                            Each vault tracks two curves: V<sub>model</sub>(t) vs V<sub>HODL</sub>(t). Performance fees
                                            are charged only on positive spread V<sub>model</sub> − V<sub>HODL</sub> using a high-water
                                            mark. This aligns fees with genuine alpha delivery.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">Vault Isolation</h5>
                                        <p className="text-xs text-white/60">
                                            Each vault operates as an independent smart contract with its own NAV, risk profile, and
                                            capital pool. A drawdown or exploit in one vault does not propagate to others — a critical
                                            design choice learned from historical DeFi failures.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">Execution Infrastructure</h5>
                                        <p className="text-xs text-white/60">
                                            Strategy signals are generated off-chain by the GP engine. Execution is anchored on
                                            Hyperliquid — a high-performance Layer 1 with sub-second finality, shared-state composability
                                            between smart contracts and a native order book, and no bridge attack surface. Strategy
                                            fills are recorded on-chain for full auditability. The modular adapter architecture
                                            supports additional venues as the protocol expands cross-chain.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">Deposits & Redemptions</h5>
                                        <p className="text-xs text-white/60">
                                            Users deposit the benchmark asset directly and receive vault shares. Redemption includes
                                            an unbonding period to prevent front-running and bank runs. Share prices mechanically
                                            reflect accumulated alpha.
                                        </p>
                                    </div>
                                </div>
                            </div>

                            {/* Layer 2: Evolutionary Engine */}
                            <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6">
                                <div className="flex items-center gap-3 mb-4">
                                    <span className="px-2 py-1 bg-amber-500/20 text-amber-500 text-xs font-bold rounded">LAYER 2</span>
                                    <h4 className="text-white font-semibold text-lg">Evolutionary Alpha Engine</h4>
                                </div>
                                <p className="text-sm text-white/60 mb-4">
                                    A proprietary genetic programming (GP) engine continuously evolves trading strategies.
                                    Unlike conventional ML models with fixed architectures, GP
                                    <strong className="text-white/90"> discovers entirely new rule structures</strong> through
                                    evolutionary selection — adapting to market regime changes without human intervention. The
                                    core objective: buy assets at a discount to fair value and sell at a premium, capturing
                                    regime transitions rather than predicting direction. Strategies rotate between long exposure,
                                    cash equivalents, and short positions based on detected market conditions — always within
                                    hard-coded risk rails that are immutable at the contract level.
                                </p>
                                <div className="grid md:grid-cols-2 gap-4">
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">Multi-Objective Fitness</h5>
                                        <p className="text-xs text-white/60">
                                            Strategy fitness penalises excessive drawdown, high turnover, slippage, leverage abuse,
                                            and poor out-of-sample generalisation. Results: strategies optimised for risk-adjusted
                                            alpha, not raw returns.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">Asset-Specific Evolution</h5>
                                        <p className="text-xs text-white/60">
                                            Each vault runs its own evolutionary process. BTC&apos;s macro-driven behaviour differs
                                            from SOL&apos;s retail-sentiment dynamics. Asset-specific evolution captures these
                                            microstructural differences.
                                        </p>
                                    </div>
                                </div>
                                <div className="mt-4 rounded-xl border border-[#0d80fa]/20 bg-[#0d80fa]/5 backdrop-blur-sm p-4 text-sm">
                                    <p className="text-white/60">
                                        <strong className="text-[#0d80fa]">IP Note:</strong> Specific fitness functions, parameter ranges,
                                        ensemble methods, and crossover operators are proprietary and not disclosed.
                                    </p>
                                </div>
                            </div>

                            {/* Layer 3: ZENT Token */}
                            <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6">
                                <div className="flex items-center gap-3 mb-4">
                                    <span className="px-2 py-1 bg-gradient-to-r from-amber-500 to-amber-600 text-white text-xs font-bold rounded">LAYER 3</span>
                                    <h4 className="text-white font-semibold text-lg">ZENT Meta-Token</h4>
                                </div>
                                <div className="grid md:grid-cols-2 gap-4">
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">Access & Staking</h5>
                                        <p className="text-xs text-white/60">
                                            Users must stake at least the <strong className="text-white/80">minStake</strong> threshold
                                            of ZENT to unlock vault access. There is no proportional TVL-to-staking requirement —
                                            a flat minimum threshold applies. This creates baseline demand tied to protocol growth,
                                            as each new depositor must acquire and lock ZENT to participate.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">Performance Fees</h5>
                                        <p className="text-xs text-white/60">
                                            20% performance fee charged only on positive alpha above HODL baseline. Fee serves as
                                            ZENT buyback/burn — creating deflationary pressure proportional to real vault performance.
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </section>

                    {/* ─── 4  The Team ───────────────────────────── */}
                    <section className="rounded-3xl border border-white/[0.1] bg-black/40 backdrop-blur-xl -mx-6 px-6 py-16 md:-mx-8 md:px-8">
                        <SectionHeading id="team" icon={Users} number="04" title="The Team" />
                        <div className="space-y-6 text-white/70 leading-relaxed">
                            <p className="text-center max-w-2xl mx-auto">
                                Built by founders with deep expertise in quantitative trading, crypto-native operations, and smart contract development.
                            </p>

                            <div className="grid md:grid-cols-3 gap-6">
                                {/* Edge */}
                                <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6 text-center">
                                    <div className="w-20 h-20 rounded-full bg-gradient-to-br from-[#0d80fa] to-[#0d80fa]/50 mx-auto mb-4 flex items-center justify-center">
                                        <span className="text-2xl font-bold text-white">E</span>
                                    </div>
                                    <h4 className="text-white font-semibold text-lg mb-1">Edge</h4>
                                    <p className="text-amber-500 text-sm font-medium mb-4">Founder — Head of Strategy</p>
                                    <p className="text-sm text-white/60 leading-relaxed">
                                        Quantitative analyst and multi-asset trader. Has designed and managed algorithmic trading systems across
                                        multiple asset classes, with a proven track record of managing millions in assets under management through
                                        systematic strategies.
                                    </p>
                                </div>

                                {/* Shaman */}
                                <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6 text-center">
                                    <div className="w-20 h-20 rounded-full bg-gradient-to-br from-[#0d80fa] to-[#0d80fa]/50 mx-auto mb-4 flex items-center justify-center">
                                        <span className="text-2xl font-bold text-white">S</span>
                                    </div>
                                    <h4 className="text-white font-semibold text-lg mb-1">Shaman</h4>
                                    <p className="text-amber-500 text-sm font-medium mb-4">Founder — Head of Operations</p>
                                    <p className="text-sm text-white/60 leading-relaxed">
                                        Serial entrepreneur with over five years of hands-on experience in the cryptocurrency space. Brings
                                        deep knowledge of crypto-native operations, community building, and protocol-level economics.
                                    </p>
                                </div>

                                {/* n0de */}
                                <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6 text-center">
                                    <div className="w-20 h-20 rounded-full bg-gradient-to-br from-[#0d80fa] to-[#0d80fa]/50 mx-auto mb-4 flex items-center justify-center">
                                        <span className="text-2xl font-bold text-white">N</span>
                                    </div>
                                    <h4 className="text-white font-semibold text-lg mb-1">n0de</h4>
                                    <p className="text-amber-500 text-sm font-medium mb-4">Founder — Head of Engineering</p>
                                    <p className="text-sm text-white/60 leading-relaxed">
                                        Smart contract and token engineer responsible for the protocol's on-chain infrastructure. Specialises
                                        in building secure, gas-efficient DeFi primitives and has contributed to multiple audited protocols.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </section>

                    {/* ─── 5  Risk Controls & Verification ───────── */}
                    <section>
                        <SectionHeading id="risk" icon={ShieldCheck} number="05" title="Risk Controls & Verification" />
                        <div className="space-y-6 text-white/70 leading-relaxed">
                            <p>
                                Risk management at Zentory is not a back-office detail — it is a
                                <strong className="text-white/90"> first-class product feature</strong>. Hard-coded risk rails are
                                enforced at the smart-contract level and are immutable or require supermajority governance + timelocks
                                to modify.
                            </p>

                            {/* On-Chain Risk Controls */}
                            <div className="rounded-2xl border border-[#0d80fa]/20 bg-[#0d80fa]/5 backdrop-blur-xl p-6">
                                <h3 className="text-white font-semibold mb-4 flex items-center gap-2">
                                    <ShieldCheck className="w-5 h-5 text-[#0d80fa]" />
                                    On-Chain Risk Controls
                                </h3>
                                <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
                                    {[
                                        { title: 'Maximum Leverage Cap', desc: 'Hard-coded limit on gross leverage per vault. Cannot be exceeded by any strategy, regardless of backtested fitness.' },
                                        { title: 'Drawdown Circuit Breaker', desc: 'If realised drawdown in any epoch exceeds a threshold, the vault automatically de-risks to stable assets and halts new positions.' },
                                        { title: 'Position Size Limits', desc: 'Maximum allocation to any single instrument or venue, preventing concentration risk.' },
                                        { title: 'Oracle Sanity Checks', desc: 'Pricing feeds validated across multiple sources. Rebalancing halts if feed divergence exceeds limits.' },
                                        { title: 'Venue Allowlists', desc: 'Strategy contracts can only interact with approved, audited execution venues — never arbitrary addresses.' },
                                        { title: 'Emergency Pause', desc: 'Multi-signature pause mechanism that halts new deposits and rebalancing while keeping redemptions available.' },
                                    ].map((item, i) => (
                                        <div key={i} className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                            <h4 className="text-white font-semibold text-sm mb-2">{item.title}</h4>
                                            <p className="text-xs text-white/60 leading-relaxed">{item.desc}</p>
                                        </div>
                                    ))}
                                </div>
                            </div>

                            {/* Transparency & Verification */}
                            <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-6">
                                <h3 className="text-white font-semibold mb-4 flex items-center gap-2">
                                    <Eye className="w-5 h-5 text-[#0d80fa]" />
                                    Transparency & Verification
                                </h3>
                                <p className="text-sm text-white/60 mb-4">
                                    Zentory is designed so that investors <strong className="text-white/90">verify, not believe</strong>.
                                    Every claim the protocol makes is backed by queryable, on-chain data.
                                </p>
                                <div className="grid md:grid-cols-2 gap-4">
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h4 className="text-white/90 font-semibold text-sm mb-3">On-Chain Data</h4>
                                        <ul className="space-y-2 text-xs text-white/60">
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-[#0d80fa] mt-1.5 flex-shrink-0" />
                                                Vault NAV per share — updated via oracle, queryable by anyone
                                            </li>
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-[#0d80fa] mt-1.5 flex-shrink-0" />
                                                HODL baseline tracking — independent benchmark comparison
                                            </li>
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-[#0d80fa] mt-1.5 flex-shrink-0" />
                                                Trade logs — every position open/close recorded on-chain
                                            </li>
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-[#0d80fa] mt-1.5 flex-shrink-0" />
                                                Drawdown and risk metrics — publicly visible per vault
                                            </li>
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-[#0d80fa] mt-1.5 flex-shrink-0" />
                                                Strategy epoch history — parameter hashes published to IPFS
                                            </li>
                                        </ul>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h4 className="text-white/90 font-semibold text-sm mb-3">Additional Safety Measures</h4>
                                        <ul className="space-y-2 text-xs text-white/60">
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-amber-500 mt-1.5 flex-shrink-0" />
                                                Timelocked upgrades — governance cannot instantly change risk parameters
                                            </li>
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-amber-500 mt-1.5 flex-shrink-0" />
                                                Isolated vaults — no shared collateral pool between asset models
                                            </li>
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-amber-500 mt-1.5 flex-shrink-0" />
                                                Insurance reserve funded by a percentage of performance fees
                                            </li>
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-amber-500 mt-1.5 flex-shrink-0" />
                                                Multiple independent smart contract audits prior to mainnet deployment
                                            </li>
                                            <li className="flex items-start gap-2">
                                                <div className="w-1.5 h-1.5 rounded-full bg-amber-500 mt-1.5 flex-shrink-0" />
                                                Active bug bounty program
                                            </li>
                                        </ul>
                                    </div>
                                </div>
                            </div>

                            {/* Roadmap to zkML */}
                            <div className="rounded-2xl border border-[#0d80fa]/20 bg-[#0d80fa]/5 backdrop-blur-xl p-6">
                                <h3 className="text-white font-semibold mb-3 flex items-center gap-2">
                                    <Eye className="w-5 h-5 text-[#0d80fa]" />
                                    Roadmap to zkML
                                </h3>
                                <p className="text-sm text-white/60">
                                    Zero-Knowledge Machine Learning (zkML) will enable cryptographic proofs that a specific
                                    GP-evolved algorithm executed a specific trade — without revealing the algorithm&apos;s code.
                                    This eliminates IP exposure risk while providing trustless execution verification.
                                </p>
                                <p className="text-sm text-white/60 mt-3">
                                    Phase 1 uses signed trade logs and strategy parameter hashes. Full zkML proofs are planned as the
                                    technology matures and becomes gas-efficient on supported chains.
                                </p>
                            </div>
                        </div>
                    </section>

                    {/* ─── 6  Tokenomics Overview ───────────────── */}
                    <section className="rounded-3xl border border-white/[0.1] bg-black/40 backdrop-blur-xl -mx-6 px-6 py-16 md:-mx-8 md:px-8">
                        <SectionHeading id="tokenomics" icon={Coins} number="06" title="Tokenomics Overview" variant="amber" />
                        <div className="space-y-6 text-white/70 leading-relaxed">

                            {/* Why This Section Was Updated */}
                            <div className="rounded-2xl border border-amber-500/20 bg-amber-500/5 backdrop-blur-xl p-5">
                                <p className="text-sm text-white/80">
                                    <strong className="text-amber-500">Design principle:</strong> This tokenomics section was revised using empirical data from 2024–2026 token launches.
                                    Tokens with multi-utility design, balanced circulating supply (40–60% at TGE), and mechanical value return mechanisms (buyback + burn)
                                    showed 2.1x better price retention than governance-only or dividend-distributing tokens. ZENT is designed accordingly.
                                </p>
                            </div>

                            {/* Two Separate Instruments */}
                            <div>
                                <h3 className="text-white font-semibold text-lg mb-3">Two Instruments, Two Roles</h3>
                                <div className="grid md:grid-cols-2 gap-5">
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-5">
                                        <h4 className="text-amber-500 font-semibold mb-2">Vault Shares (zBTC, zETH, zSOL, zXRP)</h4>
                                        <p className="text-sm text-white/60 leading-relaxed">
                                            These are what you hold to outperform HODL. Vault shares are ERC-4626 tokens representing your proportional ownership
                                            of the vault&apos;s strategy. When the GP engine generates alpha above the benchmark, vault share price rises.
                                            When strategies rotate to cash/USDT during bear regimes, vault shares hold their value versus the underlying asset.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-5">
                                        <h4 className="text-amber-500 font-semibold mb-2">ZENT Token (Layer 3 Meta-Token)</h4>
                                        <p className="text-sm text-white/60 leading-relaxed">
                                            ZENT is not a security and does not pay dividends. ZENT is a utility and governance token: staking ZENT grants vault access,
                                            ZENT holders govern the protocol, and ZENT&apos;s value appreciates through deflationary pressure — not distributions.
                                        </p>
                                    </div>
                                </div>
                            </div>

                            {/* ZENT Four Functions */}
                            <div>
                                <h3 className="text-white font-semibold text-lg mb-3">ZENT Token: Four Functions</h3>
                                <div className="grid md:grid-cols-2 gap-5">
                                    {[
                                        {
                                            title: '1. Access Key',
                                            desc: 'Staking ZENT is required to access alpha vaults. Token demand is organically tied to TVL — more vault deposits require more ZENT staked, removing it from circulation.',
                                        },
                                        {
                                            title: '2. Deflationary Mechanism',
                                            desc: '50% of all vault performance fees are used to buy back ZENT from the open market and permanently burn it. As vault TVL grows, buyback pressure compounds, reducing circulating supply.',
                                        },
                                        {
                                            title: '3. Governance',
                                            desc: 'ZENT holders vote on risk parameters, new strategy approvals, chain expansions, and protocol upgrades through a decentralised governance process.',
                                        },
                                        {
                                            title: '4. Strategy Bonding',
                                            desc: 'Model providers must stake ZENT behind their strategies. Underperforming strategies face ZENT slashing — ensuring only quality strategies receive depositor capital.',
                                        },
                                    ].map((item, i) => (
                                        <div key={i} className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-5">
                                            <h4 className="text-white font-semibold mb-2">{item.title}</h4>
                                            <p className="text-sm text-white/60 leading-relaxed">{item.desc}</p>
                                        </div>
                                    ))}
                                </div>
                            </div>

                            {/* Supply and Allocation */}
                            <div>
                                <h3 className="text-white font-semibold text-lg mb-3">ZENT Supply & Allocation</h3>
                                <p className="text-sm text-white/60 mb-4">
                                    Fixed total supply of <strong className="text-amber-500">1,000,000,000 ZENT</strong>. No admin mint key — supply is permanent
                                    and immutably capped. All allocation is in smart contracts, programmatically released on schedule.
                                </p>
                                <div className="overflow-x-auto">
                                    <table className="w-full text-sm text-left">
                                        <thead>
                                            <tr className="border-b border-white/10">
                                                <th className="py-2 pr-3 font-semibold text-white/90">Allocation</th>
                                                <th className="py-2 px-3 font-semibold text-white/90 w-20">%</th>
                                                <th className="py-2 px-3 font-semibold text-white/90 w-20">Tokens</th>
                                                <th className="py-2 pl-3 font-semibold text-white/90">Vesting Schedule</th>
                                            </tr>
                                        </thead>
                                        <tbody className="text-white/70">
                                            <tr className="border-b border-white/5">
                                                <td className="py-2 pr-3 font-medium text-white/90">Community & Ecosystem</td>
                                                <td className="py-2 px-3 text-amber-500 font-medium">45%</td>
                                                <td className="py-2 px-3">450M</td>
                                                <td className="py-2 pl-3">50% at TGE; 50% linearly over 24 months</td>
                                            </tr>
                                            <tr className="border-b border-white/5">
                                                <td className="py-2 pr-3 font-medium text-white/90">Strategy Incentives</td>
                                                <td className="py-2 px-3 text-amber-500 font-medium">10%</td>
                                                <td className="py-2 px-3">100M</td>
                                                <td className="py-2 pl-3">KPI-gated releases for top-performing vault strategies</td>
                                            </tr>
                                            <tr className="border-b border-white/5">
                                                <td className="py-2 pr-3 font-medium text-white/90">Core Team</td>
                                                <td className="py-2 px-3 text-amber-500 font-medium">18%</td>
                                                <td className="py-2 px-3">180M</td>
                                                <td className="py-2 pl-3">12-month cliff; 36-month linear vest</td>
                                            </tr>
                                            <tr className="border-b border-white/5">
                                                <td className="py-2 pr-3 font-medium text-white/90">Early Backers</td>
                                                <td className="py-2 px-3 text-amber-500 font-medium">15%</td>
                                                <td className="py-2 px-3">150M</td>
                                                <td className="py-2 pl-3">6-month cliff; 24-month linear vest</td>
                                            </tr>
                                            <tr className="border-b border-white/5">
                                                <td className="py-2 pr-3 font-medium text-white/90">Protocol Treasury</td>
                                                <td className="py-2 px-3 text-amber-500 font-medium">12%</td>
                                                <td className="py-2 px-3">120M</td>
                                                <td className="py-2 pl-3">DAO-governed; released per approved proposals</td>
                                            </tr>
                                        </tbody>
                                    </table>
                                </div>
                                <p className="text-xs text-white/40 mt-3">
                                    TGE = Token Generation Event. Team vesting is longer than investor vesting — a deliberate signal of alignment.
                                    All team and investor allocations are in time-locked smart contracts, not externally owned accounts.
                                </p>
                            </div>

                            {/* Performance Fee Architecture */}
                            <div className="rounded-2xl border border-amber-500/20 bg-amber-500/5 backdrop-blur-xl p-6">
                                <h3 className="text-white font-semibold text-lg mb-4 flex items-center gap-2">
                                    <Coins className="w-5 h-5 text-amber-500" />
                                    How ZENT Outperforms HODL: The Fee Architecture
                                </h3>
                                <p className="text-sm text-white/70 mb-5">
                                    Performance fees are only charged when strategies generate genuine alpha above the HODL baseline — with a high-water mark
                                    ensuring fees are never charged on unrealised or below-benchmark performance. The 20% performance fee is collected by the
                                    vault and forwarded to the <strong className="text-white/80">FeeDistributor</strong> contract, which enforces the
                                    50/25/15/10 split on-chain:
                                </p>
                                <div className="grid md:grid-cols-2 gap-4 mb-5">
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">
                                            50% — ZENT Buyback &amp; Burn
                                        </h5>
                                        <p className="text-xs text-white/60">
                                            Fees used to purchase ZENT from the open market and permanently remove it from circulation.
                                            This creates compounding deflationary pressure proportional to vault performance.
                                            No dividends are paid to ZENT holders — growth is captured through scarcity.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">
                                            25% — GP Engine / Strategy Creators
                                        </h5>
                                        <p className="text-xs text-white/60">
                                            Funds ongoing development of the genetic programming research engine — the protocol&apos;s
                                            primary competitive moat. Better strategies attract more TVL, creating a self-reinforcing loop.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">
                                            15% — Insurance Reserve
                                        </h5>
                                        <p className="text-xs text-white/60">
                                            A drawdown buffer funded by vault performance. Protects depositors against extreme
                                            market events. Governed by DAO; accessible only via approved proposals.
                                        </p>
                                    </div>
                                    <div className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                        <h5 className="text-white/90 font-semibold text-sm mb-2">
                                            10% — Protocol Treasury
                                        </h5>
                                        <p className="text-xs text-white/60">
                                            Covers operations, smart contract audits, legal costs, and team vesting releases.
                                            Fully transparent — treasury holdings are publicly verifiable on-chain.
                                        </p>
                                    </div>
                                </div>
                                <div className="rounded-xl border border-[#0d80fa]/20 bg-[#0d80fa]/5 backdrop-blur-sm p-3 text-xs text-white/60">
                                    <strong className="text-[#0d80fa]">On-chain FeeDistributor:</strong> The 50/25/15/10 split is enforced by the{' '}
                                    <code className="text-white/70">FeeDistributor</code> contract. Each vault forwards its performance fee to its
                                    dedicated FeeDistributor instance — all verifiable on-chain at the addresses published in the contract registry.
                                </div>
                                <p className="text-xs text-white/50 border-t border-white/10 pt-4">
                                    <strong className="text-white/70">Why no dividend distributions to ZENT holders:</strong> ZENT is structured as a utility and
                                    governance token — not a security. Paying ZENT holders a pro-rata share of vault profits would classify ZENT as a
                                    security under SEC Howey test and MiCA regulations. The buyback &amp; burn mechanism achieves the same economic effect
                                    (ZENT holders benefit from protocol growth) without regulatory risk.
                                </p>
                            </div>

                            {/* How ZENT Grows — Honest Explanation */}
                            <InfoCard title="How ZENT Outperforms HODL: The Honest Answer">
                                <p className="text-sm">
                                    ZENT does not directly hold BTC, ETH, or SOL. ZENT&apos;s value grows through two compounding mechanisms:
                                </p>
                                <ul className="list-disc list-inside space-y-1 mt-2 text-sm">
                                    <li>
                                        <strong className="text-white/80">Deflation:</strong> As vault TVL grows and performance fees accumulate, more ZENT is bought back and burned.
                                        Circulating supply shrinks. Early holders benefit most from compounding scarcity.
                                    </li>
                                    <li>
                                        <strong className="text-white/80">Access demand:</strong> More TVL requires more ZENT staked for vault access, removing ZENT from circulation.
                                        Each new depositor removes ZENT from the market permanently while they are staked.
                                    </li>
                                </ul>
                                <p className="text-sm mt-3">
                                    The vault shares (zBTC, zETH, zSOL, zXRP) deliver the alpha. ZENT captures the protocol&apos;s growth. In protocols
                                    with genuine alpha delivery and sustained TVL growth, this mechanism has historically produced price appreciation that
                                    outpaces passive HODL of the underlying assets. The GP engine&apos;s verified on-chain track record — published from
                                    day one of Genesis phase — is the foundation of this claim.
                                </p>
                                <p className="text-sm mt-3">
                                    <strong className="text-white/90">Critically: no yield is ever paid from token emissions.</strong> All vault rewards
                                    derive from real trading performance. If the GP engine underperforms the HODL baseline, no performance fees are
                                    generated and no ZENT is burned.
                                </p>
                            </InfoCard>

                            {/* Anti-Rug Protections */}
                            <div>
                                <h3 className="text-white font-semibold text-lg mb-3">Anti-Rug &amp; Governance Protections</h3>
                                <div className="grid md:grid-cols-3 gap-4">
                                    {[
                                        { title: 'No Admin Mint Key', desc: 'ZENT supply is fixed at 1B. Minting is permanently disabled in the smart contract at launch.' },
                                        { title: 'Programmatic Vesting', desc: 'All team and investor allocations are in time-locked smart contracts — not EOA wallets. Tokens release automatically on schedule.' },
                                        { title: 'LP Locked in Contract', desc: 'Initial DEX liquidity is locked for a minimum of 2 years in a smart contract. LP cannot be removed unilaterally.' },
                                        { title: 'Multi-Audit Requirement', desc: 'All smart contracts undergo at least two independent security audits before mainnet deployment.' },
                                        { title: 'DAO-Governed Treasury', desc: 'Protocol treasury is controlled by ZENT governance. Funds are only accessible via approved on-chain proposals.' },
                                        { title: 'Immutable Risk Parameters', desc: 'Vault risk parameters (max leverage, circuit breaker thresholds, position size limits) are immutable constants set at the constructor — no governance or admin can change them after deployment.' },
                                        { title: 'Governed Access Control', desc: 'Vault uses OpenZeppelin AccessControl. The GOVERNOR_ROLE can adjust minStake and fee recipients via timelock governance — no single EOA can unilaterally drain vault funds.' },
                                    ].map((item, i) => (
                                        <div key={i} className="rounded-xl border border-white/[0.1] bg-black/40 backdrop-blur-sm p-4">
                                            <h4 className="text-white/90 font-semibold text-sm mb-1">{item.title}</h4>
                                            <p className="text-xs text-white/60">{item.desc}</p>
                                        </div>
                                    ))}
                                </div>
                            </div>

                            {/* Full Fee Table */}
                            <InfoCard title="Complete fee schedule">
                                <div className="overflow-x-auto">
                                    <table className="w-full text-sm text-left">
                                        <thead>
                                            <tr className="border-b border-white/10">
                                                <th className="py-2 pr-3 font-semibold text-white/90">Action</th>
                                                <th className="py-2 px-3 font-semibold text-white/90 w-20">Rate</th>
                                                <th className="py-2 pl-3 font-semibold text-white/90">Detail</th>
                                            </tr>
                                        </thead>
                                        <tbody className="text-white/70">
                                            <tr className="border-b border-white/5"><td className="py-2 pr-3">Performance fee (on alpha above HODL benchmark)</td><td className="py-2 px-3 text-amber-500 font-medium">20%</td><td className="py-2 pl-3">Charged only on new gains above prior high-water mark. No fee on unrealised or below-benchmark performance.</td></tr>
                                            <tr className="border-b border-white/5"><td className="py-2 pr-3">Management fee</td><td className="py-2 px-3 text-amber-500 font-medium">0%</td><td className="py-2 pl-3">No annual or monthly management fee.</td></tr>
                                            <tr className="border-b border-white/5"><td className="py-2 pr-3">Deposit / mint</td><td className="py-2 px-3 text-amber-500 font-medium">0%</td><td className="py-2 pl-3">No fee to deposit into vaults or mint vault shares.</td></tr>
                                            <tr className="border-b border-white/5"><td className="py-2 pr-3">Redemption / withdrawal</td><td className="py-2 px-3 text-amber-500 font-medium">0%</td><td className="py-2 pl-3">No fee to redeem vault shares or withdraw assets.</td></tr>
                                            <tr className="border-b border-white/5"><td className="py-2 pr-3">Of the 20% performance fee</td><td className="py-2 px-3 text-amber-500 font-medium">—</td><td className="py-2 pl-3">50% to ZENT buyback &amp; burn; 25% to GP engine / strategy creators; 15% to insurance reserve; 10% to protocol treasury.</td></tr>
                                        </tbody>
                                    </table>
                                </div>
                            </InfoCard>

                        </div>
                    </section>

                    {/* ─── 7  Roadmap ──────────────────────────── */}
                    <section className="rounded-3xl border border-white/[0.1] bg-black/40 backdrop-blur-xl -mx-6 px-6 py-16 md:-mx-8 md:px-8">
                        <SectionHeading id="roadmap" icon={Map} number="07" title="Roadmap" variant="amber" />
                        <div className="space-y-6 text-white/70 leading-relaxed">
                            <div className="flex flex-col gap-4">
                                {[
                                    { phase: 'Genesis', time: 'Months 1–3', items: ['BTC model only — invite-only beta', '$1M TVL cap for risk containment', 'Conservative strategy parameters', 'Publish on-chain performance from day one'], isLatest: false },
                                    { phase: 'Validation', time: 'Months 4–6', items: ['Add ETH model', 'Public beta launch', 'Establish 6-month verified track record', 'Community governance bootstrap'], isLatest: false },
                                    { phase: 'Token Launch', time: 'Months 7–9', items: ['ZENT token launch with staking mechanics', 'Fee mechanism and buyback/burn activation', 'Governance participation for ZENT holders', 'Exchange listings and liquidity provision'], isLatest: true },
                                    { phase: 'Expansion', time: 'Months 10–18', items: ['SOL and XRP models', 'Cross-chain vault deployment', 'Institutional partnerships', 'Target: $50M TVL'], isLatest: false },
                                    { phase: 'Institutional', time: 'Months 18–36', items: ['Regulated wrapper for institutional capital', 'zkML verification implementation', 'Strategic institutional partnerships', 'Target: $500M TVL'], isLatest: false },
                                ].map((phase, i) => (
                                    <div key={i} className="relative pl-8 pb-12 before:absolute before:left-[15px] before:top-0 before:h-full before:w-px before:bg-gradient-to-b before:from-[#0d80fa]/50 before:to-transparent">
                                        <div className="flex gap-5 items-start">
                                            <div className="flex flex-col items-center">
                                                <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 ${phase.isLatest ? 'bg-gradient-to-r from-amber-500 to-amber-600 border-2 border-amber-500 shadow-lg shadow-amber-500/30' : 'bg-[#0d80fa]/20 border-2 border-[#0d80fa]'}`}>
                                                    <span className={`text-xs font-bold ${phase.isLatest ? 'text-white' : 'text-[#0d80fa]'}`}>{i + 1}</span>
                                                </div>
                                                {i < 4 && <div className="w-px flex-1 bg-[#0d80fa]/20 mt-2" />}
                                            </div>
                                            <div className="pb-8">
                                                <div className="flex items-baseline gap-3 mb-2">
                                                    <h4 className={`text-lg font-semibold ${phase.isLatest ? 'text-amber-500' : 'text-white'}`}>{phase.phase}</h4>
                                                    <span className={`text-xs font-medium ${phase.isLatest ? 'text-amber-500' : 'text-[#0d80fa]'}`}>{phase.time}</span>
                                                </div>
                                                <ul className="space-y-2">
                                                    {phase.items.map((item, j) => (
                                                        <li key={j} className="text-sm text-white/60 flex items-start gap-2">
                                                            <ChevronRight className={`w-3 h-3 mt-1 flex-shrink-0 ${phase.isLatest ? 'text-amber-500' : 'text-[#0d80fa]'}`} />
                                                            {item}
                                                        </li>
                                                    ))}
                                                </ul>
                                            </div>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>
                    </section>

                    {/* ─── 8  Regulatory ───────────────────────── */}
                    <section>
                        <SectionHeading id="regulatory" icon={Scale} number="08" title="Regulatory Approach" />
                        <div className="space-y-6 text-white/70 leading-relaxed">
                            <p>
                                Zentory is designed with regulatory awareness as a competitive advantage, not an afterthought.
                            </p>

                            <div className="grid md:grid-cols-2 gap-6">
                                <InfoCard title="Token Classification">
                                    <p>
                                        ZENT is structured as a utility and access token. It provides access to vault services, governance
                                        rights, and protocol participation — not a direct claim on underlying assets or a promise of returns.
                                    </p>
                                    <p className="mt-2">
                                        Vault shares (zBTC, zETH, etc.) represent tokenised strategy positions and are treated with
                                        appropriate investor protection considerations.
                                    </p>
                                </InfoCard>
                                <InfoCard title="Dual-Rail Design">
                                    <p>
                                        The protocol is designed to support two access rails:
                                    </p>
                                    <ul className="list-disc list-inside space-y-1 mt-2">
                                        <li><strong className="text-white/90">Permissionless rail:</strong> Open-source vault + token mechanics for decentralised access</li>
                                        <li><strong className="text-white/90">Compliant rail:</strong> KYC/AML-gated wrappers for institutional and regulated capital</li>
                                    </ul>
                                </InfoCard>
                            </div>

                            <InfoCard title="Jurisdictional Awareness">
                                <p>
                                    The team proactively engages with securities counsel in target jurisdictions. Legal opinions on token
                                    structure are obtained prior to public launch. The protocol&apos;s DAO governance structure is designed
                                    with consideration for the &ldquo;sufficient decentralisation&rdquo; framework.
                                </p>
                            </InfoCard>
                        </div>
                    </section>

                    {/* ─── 9  Disclaimer ───────────────────────── */}
                    <section className="rounded-3xl border border-white/[0.1] bg-black/40 backdrop-blur-xl -mx-6 px-6 py-16 md:-mx-8 md:px-8">
                        <SectionHeading id="disclaimer" icon={FileWarning} number="09" title="Important Disclosures" />
                        <div className="space-y-6 text-white/70 leading-relaxed text-sm">
                            <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 backdrop-blur-sm p-5">
                                <p className="mb-3">
                                    <strong className="text-amber-500">Risk Warning:</strong> Cryptocurrency trading and investment carry
                                    substantial risk. Past performance, including backtested results, does not guarantee future returns.
                                </p>
                                <ul className="list-disc list-inside space-y-1 text-white/60">
                                    <li>Genetic programming strategies may underperform or fail during unprecedented market conditions</li>
                                    <li>Smart contract vulnerabilities remain a non-zero risk despite audits</li>
                                    <li>Oracle manipulation, execution slippage, and venue failures can impact outcomes</li>
                                    <li>Regulatory changes may affect protocol operations in certain jurisdictions</li>
                                    <li>Token value is subject to market forces beyond protocol performance</li>
                                </ul>
                            </div>
                            <p>
                                Nothing in this whitepaper constitutes financial, investment, legal, or tax advice. Prospective
                                participants should conduct independent due diligence and consult qualified advisors before making any
                                decisions. The information herein is provided &ldquo;as is&rdquo; without warranty.
                            </p>
                            <LegalDisclaimer variant="banner" className="mt-6 p-4 rounded-xl bg-white/5 border border-white/10" />
                        </div>
                    </section>

                    {/* Bottom CTA */}
                    <section className="text-center py-8">
                        <div className="inline-block rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-8 md:p-12">
                            <h2 className="text-2xl md:text-3xl font-bold text-white mb-4">Ready to learn more?</h2>
                            <p className="text-white/70 mb-8 max-w-lg mx-auto">
                                Explore our pitch deck for the investment thesis, or review full tokenomics details.
                            </p>
                            <div className="flex flex-col sm:flex-row gap-4 justify-center">
                                <Link
                                    href="/models/pitch-deck"
                                    className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-gradient-to-r from-[#0d80fa] to-[#3b82f6] text-white font-semibold shadow-lg shadow-blue-500/25 transition-all duration-300 hover:scale-[1.02] hover:shadow-blue-500/40"
                                >
                                    View Pitch Deck
                                    <ArrowRight className="w-4 h-4" />
                                </Link>
                                <Link
                                    href="/tokenomics"
                                    className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-gradient-to-r from-amber-500 to-amber-600 text-white font-semibold shadow-lg shadow-amber-500/25 transition-all duration-300 hover:scale-[1.02] hover:shadow-amber-500/40"
                                >
                                    Tokenomics
                                </Link>
                                <Link
                                    href="/community"
                                    className="inline-flex items-center gap-2 px-6 py-3 rounded-xl border border-white/20 text-white/80 hover:text-white hover:border-white/40 font-medium transition-all duration-300"
                                >
                                    Join Community
                                </Link>
                            </div>
                        </div>
                    </section>
                </article>
            </div>
        </div>
    )
}
