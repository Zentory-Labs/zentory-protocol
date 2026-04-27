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

                {/* Logo */}
                <Link href="/" className="mb-6">
                  <Image
                    src="/zentory_logo_light.png"
                    alt="Zentory Labs"
                    width={160}
                    height={45}
                    className="h-10 w-auto object-contain"
                    style={{ opacity: 0.75 }}
                  />
                </Link>

                {/* Legal & risk disclosure section — lifted container */}
                <div
                  className="w-full max-w-2xl rounded-2xl p-5 mb-6"
                  style={{ background: "#111114", border: "1px solid rgba(42,47,58,0.6)" }}
                >
                  <p className="text-[11px] uppercase tracking-wider font-semibold mb-3" style={{ color: "rgba(191,195,199,0.65)", fontFamily: "'Montserrat', sans-serif" }}>
                    Legal &amp; risk disclosure
                  </p>
                  <LegalDisclaimer variant="footer" className="mb-4" />
                  <p className="text-[12px] leading-relaxed" style={{ color: "rgba(191,195,199,0.6)", fontFamily: "'Montserrat', sans-serif" }}>
                    Materials on this site have been prepared for general informational purposes only and do not constitute financial, legal, tax, or investment advice. No offer or solicitation to buy or sell any security, token, or product is made. Zentory Labs Token and Zentory Labs Models involve risk; past or hypothetical performance does not guarantee future results. Access may be restricted by jurisdiction. You should seek independent legal, tax, and financial advice before making any decision.
                  </p>
                </div>

                {/* Links */}
                <div className="flex flex-col sm:flex-row items-center justify-center gap-4 sm:gap-6 text-xs" style={{ color: "rgba(191,195,199,0.6)", fontFamily: "'Montserrat', sans-serif" }}>
                  <span>© {currentYear} Zentory Labs</span>
                  <a href="https://zentorylabs.com/terms-of-service" target="_blank" rel="noopener noreferrer" className="transition-colors hover:!text-[#b08d57]" style={{ color: "rgba(191,195,199,0.6)" }}>
                    Terms of Service
                  </a>
                  <a href="https://zentorylabs.com/privacy-policy" target="_blank" rel="noopener noreferrer" className="transition-colors hover:!text-[#b08d57]" style={{ color: "rgba(191,195,199,0.6)" }}>
                    Privacy Policy
                  </a>
                </div>

              </div>
            </div>

            {/* Risk disclaimer strip */}
            <div
              className="py-5 px-6 border-t"
              style={{ background: "#0d0d10", borderColor: "rgba(42,47,58,0.5)" }}
            >
              <p className="text-center text-[13px]" style={{ color: "rgba(191,195,199,0.55)", fontFamily: "'Montserrat', sans-serif" }}>
                Not financial or legal advice. No offer or solicitation. High risk. Seek independent advice. See{' '}
                <a href="https://zentorylabs.com/terms-of-service" target="_blank" rel="noopener noreferrer" className="underline hover:text-[#b08d57]" style={{ color: "rgba(191,195,199,0.55)" }}>
                  Terms
                </a>{' '}
                and risk disclosures.
              </p>
            </div>

            {/* Full legal disclosure */}
            <div
              className="py-10 px-6 border-t"
              style={{ background: "#0d0d10", borderColor: "rgba(42,47,58,0.4)" }}
            >
              <div
                className="max-w-3xl mx-auto rounded-2xl p-5"
                style={{ background: "#0d0d10", border: "1px solid rgba(42,47,58,0.3)" }}
              >
                <h3 className="text-[11px] uppercase tracking-widest font-semibold mb-3" style={{ color: "rgba(191,195,199,0.5)", fontFamily: "'Montserrat', sans-serif" }}>
                  Legal &amp; Risk Disclosure
                </h3>
                <p className="text-[12px] leading-relaxed" style={{ color: "rgba(191,195,199,0.5)", fontFamily: "'Montserrat', sans-serif" }}>
                  This website and all materials have been prepared for general informational purposes only and do not constitute financial, legal, tax, or investment advice. No offer or solicitation to buy or sell any security, token, or product is made. Zentory Labs Token and Zentory Labs Models involve risk; past or hypothetical performance does not guarantee future results. Access may be restricted by jurisdiction. Zentory Protocol utilizes genetic programming and algorithmic trading strategies which carry substantial risk of loss. You should seek independent legal, tax, and financial advice before making any decision.
                </p>
              </div>
            </div>
          </footer>
        </Providers>
        <Analytics />
      </body>
    </html>
  );
}
