import { NextResponse } from "next/server";
import { createClient } from "@/utils/supabase/server";

/**
 * GET /api/markets-signals
 * Server-side proxy for the Markets page live signal feed.
 * Reads from Supabase directly (no CORS/RPC issues).
 */
export async function GET() {
  let supabase;
  try {
    supabase = await createClient();
  } catch (err) {
    console.error("[GET /api/markets-signals] createClient failed:", err);
    return NextResponse.json({ signals: [], error: String(err) }, { status: 500 });
  }

  try {
    const { data, error } = await supabase
      .from("signals")
      .select("id, provider, asset, direction, price, created_at")
      .order("created_at", { ascending: false })
      .limit(20);

    if (error) {
      console.error("[GET /api/markets-signals] query error:", error.message);
      return NextResponse.json({ signals: [], error: error.message }, { status: 200 });
    }

    return NextResponse.json({ signals: data ?? [], count: data?.length ?? 0 });
  } catch (err) {
    console.error("[GET /api/markets-signals] unexpected error:", err);
    return NextResponse.json({ signals: [], error: String(err) }, { status: 500 });
  }
}
