import { NextRequest, NextResponse } from "next/server";
import type { Asset, Direction, Signal, SignalStatus } from "@/lib/signals";

interface SignalEntry extends Signal {
  id: string;
  timestamp: number;
  provider: "gp" | "lumibot" | "manual";
  asset: Asset;
  direction: Direction;
  size: number;
  price: number;
  status: SignalStatus;
  txHash?: string;
}

// Module-level in-memory store
const signals: SignalEntry[] = [];

function makeId(): string {
  return `sig_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
}

export async function GET() {
  return NextResponse.json(signals);
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { asset, direction, size, price } = body as {
      asset: Asset;
      direction: Direction;
      size: number;
      price: number;
    };

    if (!asset || !direction || typeof size !== "number" || typeof price !== "number") {
      return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
    }

    const signal: SignalEntry = {
      id: makeId(),
      timestamp: Date.now(),
      provider: "manual",
      asset,
      direction,
      size,
      price,
      status: "pending",
    };

    signals.unshift(signal);
    return NextResponse.json(signal, { status: 201 });
  } catch {
    return NextResponse.json({ error: "Bad request" }, { status: 400 });
  }
}
