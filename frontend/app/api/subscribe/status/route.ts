import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/utils/supabase/server";

export const runtime = "nodejs";

export async function GET(req: NextRequest) {
  const sessionId = req.nextUrl.searchParams.get("session_id");

  if (!sessionId) {
    return NextResponse.json({ error: "session_id is required" }, { status: 400 });
  }

  const supabase = await createClient();

  const { data: sub, error } = await supabase
    .from("subscriptions")
    .select("tier_id, expires_at, status, wallet_address")
    .eq("stripe_session_id", sessionId)
    .single();

  if (error || !sub) {
    return NextResponse.json({ error: "Subscription not found" }, { status: 404 });
  }

  const tierNames = ["BASIC", "PRO", "ELITE"];

  return NextResponse.json({
    tier: tierNames[sub.tier_id as 0 | 1 | 2] ?? "UNKNOWN",
    tierId: sub.tier_id,
    expiresAt: sub.expires_at,
    status: sub.status,
    walletAddress: sub.wallet_address,
  });
}
