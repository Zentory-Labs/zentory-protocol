"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount, useBalance, useDisconnect, useConnect } from "wagmi";
import { useState } from "react";

const NAV_LINKS = [
  { href: "/", label: "Protocol" },
  { href: "/signals", label: "Signals" },
  { href: "/stake", label: "Stake" },
  { href: "/govern", label: "Govern" },
];

function shorten(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export default function Nav() {
  const pathname = usePathname();
  const { address, isConnected } = useAccount();
  const { disconnect } = useDisconnect();
  const { connect, connectors } = useConnect();
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header className="border-b border-white/10 bg-[#0d0d14]/90 backdrop-blur-sm sticky top-0 z-50">
      <div className="mx-auto max-w-7xl px-6 py-4 flex items-center justify-between">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-amber-500 flex items-center justify-center text-black font-bold text-sm">
            Z
          </div>
          <span className="font-bold text-white tracking-tight">Zentory</span>
        </Link>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-6">
          {NAV_LINKS.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className={`text-sm font-medium transition-colors ${
                pathname === href
                  ? "text-amber-400"
                  : "text-white/60 hover:text-white"
              }`}
            >
              {label}
            </Link>
          ))}
        </nav>

        {/* Wallet */}
        <div className="flex items-center gap-3">
          {isConnected && address ? (
            <div className="flex items-center gap-2">
              <div className="hidden sm:flex flex-col items-end">
                <span className="text-xs font-mono text-white">{shorten(address)}</span>
              </div>
              <button
                onClick={() => disconnect()}
                className="rounded-full border border-white/20 bg-white/5 px-3 py-1.5 text-xs text-white/60 hover:text-white hover:border-white/40 transition-colors"
              >
                Disconnect
              </button>
            </div>
          ) : (
            <button
              onClick={() => {
                for (const connector of connectors) {
                  try {
                    connect({ connector });
                    return;
                  } catch {
                    // try next
                  }
                }
              }}
              className="rounded-full bg-amber-500 hover:bg-amber-400 text-black font-semibold px-4 py-1.5 text-sm transition-colors"
            >
              Connect Wallet
            </button>
          )}

          {/* Mobile hamburger */}
          <button
            className="md:hidden text-white/60 hover:text-white"
            onClick={() => setMenuOpen(!menuOpen)}
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              {menuOpen ? (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              ) : (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
              )}
            </svg>
          </button>
        </div>
      </div>

      {/* Mobile menu */}
      {menuOpen && (
        <nav className="md:hidden border-t border-white/10 px-6 py-4 flex flex-col gap-3 bg-[#0d0d14]">
          {NAV_LINKS.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              onClick={() => setMenuOpen(false)}
              className={`text-sm font-medium ${
                pathname === href ? "text-amber-400" : "text-white/60"
              }`}
            >
              {label}
            </Link>
          ))}
        </nav>
      )}
    </header>
  );
}
