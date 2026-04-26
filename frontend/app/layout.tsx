import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/next";
import Image from "next/image";
import Link from "next/link";
import Providers from "@/components/Providers";
import Nav from "@/components/Nav";
import LegalDisclaimer from "@/components/LegalDisclaimer";
import "./globals.css";

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
  const currentYear = new Date().getFullYear();

  return (
    <html lang="en">
      <body className="min-h-screen text-white antialiased" style={{ background: "#0b0b0d" }} suppressHydrationWarning>
        <Providers>
          <Nav />
          <main className="mx-auto max-w-7xl px-6 pt-24 pb-8">
            {children}
          </main>
          <footer className="text-[#bfc3c7]" style={{ background: "#0b0b0d" }}>
            <div className="max-w-7xl mx-auto px-6 lg:px-8 py-12">
              <div className="flex flex-col items-center text-center">
                <Link href="/" className="mb-6">
                  <Image
                    src="/zentory_logo_light.png"
                    alt="Zentory Labs"
                    width={160}
                    height={45}
                    className="h-10 w-auto object-contain opacity-60"
                  />
                </Link>
                <p className="text-[10px] uppercase tracking-wider font-medium mb-3" style={{ color: "rgba(191,195,199,0.4)", fontFamily: "'Montserrat', sans-serif" }}>
                  Legal & risk disclosure
                </p>
                <LegalDisclaimer variant="footer" className="mb-6" />
                <p className="text-[10px] max-w-lg mb-8" style={{ color: "rgba(191,195,199,0.4)", fontFamily: "'Montserrat', sans-serif" }}>
                  Materials on this site have been prepared for general informational purposes only and do not constitute financial, legal, tax, or investment advice. No offer or solicitation to buy or sell any security, token, or product is made. Zentory Labs Token and Zentory Labs Models involve risk; past or hypothetical performance does not guarantee future results. Access may be restricted by jurisdiction. You should seek independent legal, tax, and financial advice before making any decision.
                </p>
                <div className="flex flex-col sm:flex-row items-center justify-center gap-4 sm:gap-6 text-xs" style={{ color: "rgba(191,195,199,0.5)", fontFamily: "'Montserrat', sans-serif" }}>
                  <span>© {currentYear} Zentory Labs</span>
                  <a href="https://zentorylabs.com/terms-of-service" target="_blank" rel="noopener noreferrer" className="transition-colors hover:!text-[#b08d57]" style={{ color: "rgba(191,195,199,0.5)" }}>
                    Terms of Service
                  </a>
                  <a href="https://zentorylabs.com/privacy-policy" target="_blank" rel="noopener noreferrer" className="transition-colors hover:!text-[#b08d57]" style={{ color: "rgba(191,195,199,0.5)" }}>
                    Privacy Policy
                  </a>
                </div>
              </div>
            </div>
          </footer>
        </Providers>
        <Analytics />
      </body>
    </html>
  );
}
