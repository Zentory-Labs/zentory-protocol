import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/utils/supabase/server";
import type { Asset, Direction, SignalProvider } from "@/lib/signals";

/**
 * POST /api/signals/log
 * Logs a trading signal to Supabase.
 *
 * Phase 1: open to anyone (testnet, no real capital at stake).
 * Phase 2: will be gated by ZENT governance — only proposals passed by
 * token holders can trigger keeper execution.
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { provider, asset, direction, size, price } = body as {
      provider: SignalProvider;
      asset: Asset;
      direction: Direction;
      size: number;
      price: number;
    };

    if (!provider || !asset || !direction || typeof size !== "number" || typeof price !== "number") {
      return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
    }

    const supabase = await createClient();
    const { data, error } = await supabase
      .from("signals")
      .insert({
        provider,
        asset,
        direction,
        size,
        price,
        status: "pending",
        tx_hash: null,
        executed_by: null,
        executor_address: null,
      })
      .select()
      .single();

    if (error) {
      console.error("[POST /api/signals/log]", error.message);
      return NextResponse.json({ error: "Failed to store signal" }, { status: 500 });
    }

    return NextResponse.json(data, { status: 201 });
  } catch (err) {
    console.error("[POST /api/signals/log]", err);
    return NextResponse.json({ error: "Bad request" }, { status: 400 });
  }
}
