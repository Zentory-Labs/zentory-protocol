"use client";

import Link from "next/link";
import Image from "next/image";
import { useState, useEffect } from "react";
import { usePathname } from "next/navigation";
import { useAccount, useDisconnect, useConnect } from "wagmi";

const NAV_LINKS = [
  { href: "/", label: "Vaults" },
  { href: "/signals", label: "Signals" },
  { href: "/stake", label: "Stake" },
  { href: "/govern", label: "Govern" },
];

function shorten(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export default function Nav() {
  const pathname = usePathname();
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isScrolled, setIsScrolled] = useState(false);
  const { address, isConnected } = useAccount();
  const { disconnect } = useDisconnect();
  const { connect, connectors } = useConnect();

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 10);
    window.addEventListener("scroll", handleScroll);
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  const navClass =
    "px-3 py-2 text-xs font-medium transition-all duration-200 uppercase tracking-[0.12em] relative group text-white/90 hover:text-white";
  const underlineClass =
    "absolute bottom-1 left-3 right-3 h-px transition-all duration-300 bg-white/0 group-hover:bg-white/40";

  return (
    <header
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-500
        backdrop-blur-2xl backdrop-saturate-150
        ${isScrolled
          ? "bg-[#05070c]/40 border-b border-white/[0.04] shadow-lg shadow-black/20"
          : "bg-[#05070c] border-b border-white/[0.06]"}`}
    >
      <nav className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-start items-center h-20 gap-8 lg:gap-10">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2.5 group flex-shrink-0 z-10">
            <Image
              src="/zentory_logo_dark.png"
              alt="Zentory Labs"
              width={44}
              height={44}
              className="h-10 w-10 object-contain transition-all duration-300 group-hover:opacity-90 brightness-0 invert"
              priority
            />
            <span
              className="font-semibold tracking-tight transition-colors duration-300 text-white"
              style={{ fontFamily: "Montserrat, sans-serif" }}
            >
              Zentory Labs
            </span>
          </Link>

          {/* Desktop nav */}
          <div className="hidden lg:flex items-center gap-1">
            {NAV_LINKS.map(({ href, label }) => {
              const isActive = pathname === href;
              return (
                <Link key={href} href={href} className={navClass}>
                  {label}
                  <span className={underlineClass} />
                  {isActive && (
                    <span className="absolute bottom-1 left-3 right-3 h-px bg-white/60" />
                  )}
                </Link>
              );
            })}
            <a
              href="https://zentorylabs.com"
              target="_blank"
              rel="noopener noreferrer"
              className={`${navClass} text-white/60 hover:text-white`}
            >
              Docs
              <span className={underlineClass} />
            </a>
            <a
              href="https://zentorylabs.com/whitepaper"
              target="_blank"
              rel="noopener noreferrer"
              className={`${navClass} text-white/60 hover:text-white`}
            >
              Whitepaper
              <span className={underlineClass} />
            </a>
          </div>

          {/* Wallet — right side */}
          <div className="flex items-center gap-3 ml-auto">
            {isConnected && address ? (
              <div className="flex items-center gap-3">
                <span className="hidden sm:block font-mono text-xs text-white/70">
                  {shorten(address)}
                </span>
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
                className="rounded-full bg-[#f59e0b] hover:bg-[#f59e0b]/90 text-black font-semibold px-5 py-2 text-xs tracking-[0.08em] uppercase transition-all duration-300 shadow-lg shadow-amber-500/20 hover:shadow-amber-500/30"
              >
                Connect
              </button>
            )}

            {/* Mobile hamburger */}
            <button
              className="lg:hidden p-2 rounded-lg text-white/90 hover:text-white hover:bg-white/10 transition-colors backdrop-blur-sm"
              onClick={() => setIsMenuOpen(!isMenuOpen)}
              aria-label="Toggle menu"
            >
              <svg
                className="h-6 w-6"
                fill="none"
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="1.5"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                {isMenuOpen ? (
                  <path d="M6 18L18 6M6 6l12 12" />
                ) : (
                  <path d="M4 6h16M4 12h16M4 18h16" />
                )}
              </svg>
            </button>
          </div>
        </div>

        {/* Mobile menu */}
        {isMenuOpen && (
          <div className="lg:hidden py-4 border-t border-white/[0.08] animate-in slide-in-from-top bg-black/50 backdrop-blur-xl">
            {NAV_LINKS.map(({ href, label }) => (
              <Link
                key={href}
                href={href}
                className="block px-4 py-3 text-white/90 hover:text-white hover:bg-white/10 font-light uppercase tracking-wider text-sm transition-colors"
                onClick={() => setIsMenuOpen(false)}
              >
                {label}
              </Link>
            ))}
            <a
              href="https://zentorylabs.com"
              target="_blank"
              rel="noopener noreferrer"
              className="block px-4 py-3 text-white/90 hover:text-white hover:bg-white/10 font-light uppercase tracking-wider text-sm transition-colors"
              onClick={() => setIsMenuOpen(false)}
            >
              Docs
            </a>
            <a
              href="https://zentorylabs.com/whitepaper"
              target="_blank"
              rel="noopener noreferrer"
              className="block px-4 py-3 text-white/90 hover:text-white hover:bg-white/10 font-light uppercase tracking-wider text-sm transition-colors"
              onClick={() => setIsMenuOpen(false)}
            >
              Whitepaper
            </a>
          </div>
        )}
      </nav>
    </header>
  );
}
