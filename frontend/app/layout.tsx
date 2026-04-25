import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Providers from "@/components/Providers";
import Nav from "@/components/Nav";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Zentory Protocol",
  description:
    "AI-powered algorithmic trading vaults built on Hyperliquid. Generate alpha through intelligent trend-following strategies.",
  icons: {
    icon: "/favicon.ico",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body className="min-h-screen bg-[#0a0a0f] text-white antialiased" suppressHydrationWarning>
        <Providers>
          <Nav />
          {children}
          <footer className="border-t border-white/10 py-8 mt-16">
            <div className="mx-auto max-w-7xl px-6 flex flex-col sm:flex-row items-center justify-between gap-4">
              <div className="flex items-center gap-2">
                <div className="w-6 h-6 rounded bg-amber-500 flex items-center justify-center text-black font-bold text-xs">Z</div>
                <span className="text-sm text-white/40">Zentory Protocol — HyperEVM Testnet</span>
              </div>
              <div className="flex gap-4 text-xs text-white/40">
                <a href="https://hypurrscan.io" target="_blank" rel="noopener noreferrer" className="hover:text-white transition-colors">Explorer</a>
                <a href="/whitepaper" className="hover:text-white transition-colors">Whitepaper</a>
                <a href="https://github.com/zentorylabs" target="_blank" rel="noopener noreferrer" className="hover:text-white transition-colors">GitHub</a>
              </div>
            </div>
          </footer>
        </Providers>
      </body>
    </html>
  );
}
