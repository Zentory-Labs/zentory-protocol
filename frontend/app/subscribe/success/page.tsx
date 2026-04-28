"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

interface SubscriptionStatus {
  tier: string;
  tierId: number;
  expiresAt: string;
  status: string;
  walletAddress?: string;
}

const TIER_EMOJI: Record<number, string> = {
  0: "🔐",
  1: "⚡",
  2: "👑",
};

const ZENT_REQUIRED: Record<number, number> = {
  0: 100,
  1: 500,
  2: 2000,
};

function SubscribeSuccessContent() {
  const searchParams = useSearchParams();
  const sessionId = searchParams.get("session_id");

  const [sub, setSub] = useState<SubscriptionStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!sessionId) {
      setError("No session ID found.");
      setLoading(false);
      return;
    }

    fetch(`/api/subscribe/status?session_id=${sessionId}`)
      .then((r) => {
        if (!r.ok) throw new Error("Subscription not found");
        return r.json();
      })
      .then((data: SubscriptionStatus) => {
        setSub(data);
        setLoading(false);
      })
      .catch((e: unknown) => {
        setError(e instanceof Error ? e.message : "Failed to load subscription");
        setLoading(false);
      });
  }, [sessionId]);

  if (loading) {
    return (
      <div
        className="min-h-screen flex items-center justify-center"
        style={{ background: "#0b0b0d", fontFamily: "'Montserrat', sans-serif" }}
      >
        <div className="text-center space-y-4">
          <div className="text-5xl">⏳</div>
          <p className="text-sm" style={{ color: "rgba(234,234,234,0.6)" }}>
            Confirming your subscription…
          </p>
        </div>
      </div>
    );
  }

  if (error || !sub) {
    return (
      <div
        className="min-h-screen flex items-center justify-center"
        style={{ background: "#0b0b0d", fontFamily: "'Montserrat', sans-serif" }}
      >
        <div
          className="p-8 rounded-2xl text-center max-w-md"
          style={{ background: "#1c1c21", border: "1px solid #2a2f3a" }}
        >
          <div className="text-4xl mb-4">❌</div>
          <h1 className="text-2xl font-bold mb-2" style={{ color: "#eaeaea" }}>
            Something went wrong
          </h1>
          <p className="text-sm mb-6" style={{ color: "rgba(234,234,234,0.6)" }}>
            {error ?? "Could not load your subscription status."}
          </p>
          <Link
            href="/subscribe"
            className="inline-block px-6 py-3 rounded-xl text-sm font-semibold"
            style={{
              background: "rgba(139,30,45,0.15)",
              border: "1px solid rgba(139,30,45,0.4)",
              color: "#c2353f",
            }}
          >
            Back to Subscribe
          </Link>
        </div>
      </div>
    );
  }

  const expiresDate = new Date(sub.expiresAt);
  const zentNeeded = ZENT_REQUIRED[sub.tierId] ?? 0;

  return (
    <div
      className="min-h-screen flex items-center justify-center px-6"
      style={{ background: "#0b0b0d", fontFamily: "'Montserrat', sans-serif" }}
    >
      {/* Ambient glow */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 w-96 h-96 bg-[#b08d57]/5 rounded-full blur-3xl pointer-events-none" />

      <div
        className="w-full max-w-lg p-8 rounded-2xl text-center space-y-6 relative"
        style={{ background: "#1c1c21", border: "1px solid #2a2f3a" }}
      >
        {/* Check icon */}
        <div
          className="w-16 h-16 rounded-full mx-auto flex items-center justify-center text-3xl"
          style={{ background: "rgba(34,197,94,0.12)", border: "1px solid rgba(34,197,94,0.3)" }}
        >
          ✓
        </div>

        {/* Tier badge */}
        <div>
          <div className="text-5xl mb-3">
            {TIER_EMOJI[sub.tierId] ?? "📦"}
          </div>
          <div
            className="inline-flex items-center gap-2 rounded-full border px-4 py-1.5 text-xs font-semibold mb-3"
            style={{
              background: "rgba(34,197,94,0.1)",
              borderColor: "rgba(34,197,94,0.3)",
              color: "#22c55e",
            }}
          >
            <span className="w-1.5 h-1.5 rounded-full" style={{ background: "#22c55e", boxShadow: "0 0 8px #22c55e" }} />
            {sub.status === "active" ? "Subscription Active" : sub.status}
          </div>
          <h1 className="text-3xl font-bold" style={{ color: "#eaeaea" }}>
            {sub.tier} Plan
          </h1>
        </div>

        {/* Details */}
        <div
          className="rounded-xl p-4 text-left space-y-3"
          style={{ background: "rgba(255,255,255,0.03)", border: "1px solid #2a2f3a" }}
        >
          <div className="flex justify-between items-center">
            <span className="text-sm" style={{ color: "rgba(234,234,234,0.5)" }}>Status</span>
            <span className="text-sm font-semibold capitalize" style={{ color: "#22c55e" }}>{sub.status}</span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-sm" style={{ color: "rgba(234,234,234,0.5)" }}>Renews</span>
            <span className="text-sm font-semibold" style={{ color: "#eaeaea" }}>
              {expiresDate.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}
            </span>
          </div>
          {sub.walletAddress && (
            <div className="flex justify-between items-center">
              <span className="text-sm" style={{ color: "rgba(234,234,234,0.5)" }}>Wallet</span>
              <span
                className="text-xs font-mono"
                style={{ color: "#b08d57" }}
              >
                {sub.walletAddress.slice(0, 6)}…{sub.walletAddress.slice(-4)}
              </span>
            </div>
          )}
        </div>

        {/* NFT notice */}
        <p className="text-sm" style={{ color: "rgba(234,234,234,0.55)" }}>
          Your subscription NFT has been activated. The keeper will mint your access token on-chain within a few minutes.
        </p>

        {/* Renewal notice */}
        <div
          className="rounded-xl p-4 text-left"
          style={{ background: "rgba(176,141,87,0.06)", border: "1px solid rgba(176,141,87,0.2)" }}
        >
          <p className="text-xs" style={{ color: "rgba(234,234,234,0.5)" }}>
            <span style={{ color: "#b08d57" }}>Renewal info:</span> When your subscription renews, you can pay with card again or switch to ZENT tokens. You will need{" "}
            <span style={{ color: "#eaeaea" }}>{zentNeeded.toLocaleString()} ZENT</span> for future renewals via crypto.
          </p>
        </div>

        {/* CTA */}
        <Link
          href="/markets"
          className="block w-full py-3 px-6 rounded-xl font-semibold text-sm text-center transition-all hover:scale-[1.02]"
          style={{
            background: "#b08d57",
            color: "#0b0b0d",
            fontFamily: "'Montserrat', sans-serif",
          }}
        >
          Browse Signal Markets
        </Link>
      </div>
    </div>
  );
}

export default function SubscribeSuccessPage() {
  return (
    <Suspense
      fallback={
        <div
          className="min-h-screen flex items-center justify-center"
          style={{ background: "#0b0b0d", fontFamily: "'Montserrat', sans-serif" }}
        >
          <div className="text-center space-y-4">
            <div className="text-5xl">⏳</div>
            <p className="text-sm" style={{ color: "rgba(234,234,234,0.6)" }}>
              Loading…
            </p>
          </div>
        </div>
      }
    >
      <SubscribeSuccessContent />
    </Suspense>
  );
}
