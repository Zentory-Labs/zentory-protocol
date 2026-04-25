"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount, useDisconnect, useConnect } from "wagmi";
import { useState } from "react";

const NAV_LINKS = [
  { href: "/", label: "Home" },
  { href: "/signals", label: "Signals" },
  { href: "/stake", label: "Stake" },
  { href: "/govern", label: "Govern" },
  { href: "/whitepaper", label: "Whitepaper" },
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
    <>
      <nav className="fixed top-0 left-0 right-0 z-50 bg-[#05070c]/40 backdrop-blur-xl border-b border-white/[0.06] shadow-lg shadow-black/20 transition-all duration-300">
        <div className="mx-auto max-w-7xl px-6 py-4 flex items-center justify-between">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-3 group">
            <svg viewBox="0 0 32 32" fill="none" className="h-9 w-9 transition-transform duration-300 group-hover:scale-110">
              <rect width="32" height="32" rx="8" fill="#0d80fa" />
              <path
                d="M8 10h16M8 10l10-4M8 10v12l10 4M18 22H8"
                stroke="white"
                strokeWidth="2.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            <span className="font-bold text-white tracking-[0.15em] uppercase text-sm">
              Zentory Labs
            </span>
          </Link>

          {/* Desktop nav */}
          <div className="hidden lg:flex items-center gap-8">
            {NAV_LINKS.map(({ href, label }) => {
              const isActive = pathname === href;
              return (
                <Link
                  key={href}
                  href={href}
                  className={`group relative text-xs font-medium tracking-[0.12em] uppercase transition-colors duration-300 ${
                    isActive ? "text-white" : "text-white/70"
                  } hover:text-white`}
                >
                  {label}
                  <span
                    className={`absolute -bottom-1 left-5 right-5 h-px bg-white/0 group-hover:bg-white/40 transition-all duration-300 ${
                      isActive ? "bg-white/60" : ""
                    }`}
                  />
                </Link>
              );
            })}
          </div>

          {/* Wallet */}
          <div className="flex items-center gap-4">
            {isConnected && address ? (
              <div className="flex items-center gap-3">
                <div className="hidden sm:flex flex-col items-end">
                  <span className="text-xs font-mono text-white/80">
                    {shorten(address)}
                  </span>
                </div>
                <button
                  onClick={() => disconnect()}
                  className="rounded-full border border-white/20 bg-white/5 px-3 py-1.5 text-xs text-white/70 hover:text-white hover:border-white/40 hover:bg-white/10 transition-all duration-300"
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
                className="rounded-full bg-[#0d80fa] hover:bg-[#0d80fa]/90 text-white font-semibold px-5 py-2 text-xs tracking-[0.08em] uppercase transition-all duration-300 shadow-lg shadow-blue-500/20 hover:shadow-blue-500/30"
              >
                Connect Wallet
              </button>
            )}

            {/* Mobile hamburger */}
            <button
              className="lg:hidden text-white/60 hover:text-white transition-colors p-1"
              onClick={() => setMenuOpen(!menuOpen)}
              aria-label="Toggle menu"
            >
              {menuOpen ? (
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              ) : (
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M4 6h16M4 12h16M4 18h16"
                  />
                </svg>
              )}
            </button>
          </div>
        </div>
      </nav>

      {/* Mobile menu */}
      {menuOpen && (
        <div className="lg:hidden fixed top-[73px] left-0 right-0 z-40 bg-[#05070c]/95 backdrop-blur-xl border-t border-white/[0.08] px-6 py-6 flex flex-col gap-5">
          {NAV_LINKS.map(({ href, label }) => {
            const isActive = pathname === href;
            return (
              <Link
                key={href}
                href={href}
                onClick={() => setMenuOpen(false)}
                className={`group relative text-sm font-medium tracking-[0.12em] uppercase transition-colors duration-300 ${
                  isActive ? "text-white" : "text-white/70"
                } hover:text-white`}
              >
                {label}
                <span
                  className={`absolute -bottom-1 left-0 right-0 h-px bg-white/0 group-hover:bg-white/40 transition-all duration-300 ${
                    isActive ? "bg-white/60" : ""
                  }`}
                />
              </Link>
            );
          })}
        </div>
      )}
    </>
  );
}
