import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/next";
import Providers from "@/components/Providers";
import Nav from "@/components/Nav";
import "./globals.css";

export const metadata: Metadata = {
  title: "Zentory Protocol",
  description:
    "AI-powered algorithmic trading vaults built on Hyperliquid. Generate alpha through intelligent trend-following strategies.",
  icons: {
    icon: "/favicon.ico",
  },
};

function FooterLogo() {
  return (
    <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg" className="text-amber-400">
      <rect width="28" height="28" rx="6" fill="currentColor" fillOpacity="0.15" />
      <path d="M7 8L14 20L21 8" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M10 8L14 15L18 8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" strokeOpacity="0.6" />
    </svg>
  );
}

function Footer() {
  const currentYear = new Date().getFullYear();

  return (
    <footer className="bg-black border-t border-white/[0.06] mt-16">
      <div className="mx-auto max-w-7xl px-6 py-10">
        <div className="grid grid-cols-1 sm:grid-cols-3 items-start gap-8">
          {/* Logo & Wordmark */}
          <div className="flex flex-col items-start gap-3">
            <div className="flex items-center gap-2.5">
              <FooterLogo />
              <span className="font-bold text-white tracking-tight">Zentory Labs</span>
            </div>
            <p className="text-xs text-white/30 max-w-[180px] leading-relaxed">
              AI-powered algorithmic trading infrastructure on Hyperliquid.
            </p>
          </div>

          {/* Links */}
          <div className="flex flex-col items-center sm:items-start gap-3">
            <span className="text-xs font-semibold text-white/40 uppercase tracking-widest">Protocol</span>
            <div className="flex flex-col gap-2">
              <a href="/" className="text-sm text-white/50 hover:text-white transition-colors">Vaults</a>
              <a href="/signals" className="text-sm text-white/50 hover:text-white transition-colors">Signals</a>
              <a href="/stake" className="text-sm text-white/50 hover:text-white transition-colors">Stake</a>
              <a href="/govern" className="text-sm text-white/50 hover:text-white transition-colors">Govern</a>
            </div>
          </div>

          {/* Social & Legal */}
          <div className="flex flex-col items-start sm:items-end gap-3">
            <span className="text-xs font-semibold text-white/40 uppercase tracking-widest">Resources</span>
            <div className="flex flex-col gap-2 items-start sm:items-end">
              <a href="/whitepaper" className="text-sm text-white/50 hover:text-white transition-colors">Whitepaper</a>
              <a href="https://github.com/zentorylabs" target="_blank" rel="noopener noreferrer" className="text-sm text-white/50 hover:text-white transition-colors">GitHub</a>
              <a href="https://hypurrscan.io" target="_blank" rel="noopener noreferrer" className="text-sm text-white/50 hover:text-white transition-colors">Explorer</a>
            </div>
            <div className="flex items-center gap-3 pt-2 border-t border-white/[0.06] w-full sm:w-auto justify-start sm:justify-end">
              <a href="/terms" className="text-xs text-white/30 hover:text-white/60 transition-colors">Terms</a>
              <span className="text-white/20">·</span>
              <a href="/privacy" className="text-xs text-white/30 hover:text-white/60 transition-colors">Privacy</a>
            </div>
          </div>
        </div>

        {/* Bottom bar */}
        <div className="mt-8 pt-6 border-t border-white/[0.06] flex flex-col sm:flex-row items-center justify-between gap-3">
          <p className="text-xs text-white/25">© {currentYear} Zentory Labs</p>
          <p className="text-xs text-white/25">HyperEVM Testnet</p>
        </div>
      </div>
    </footer>
  );
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-[#05070c] text-white antialiased" suppressHydrationWarning>
        <Providers>
          <Nav />
          <main className="mx-auto max-w-7xl px-6 pt-24 pb-8">
            {children}
          </main>
          <Footer />
        </Providers>
        <Analytics />
      </body>
    </html>
  );
}
