import { NextRequest, NextResponse } from "next/server";
import { stripe } from "@/lib/stripe";

// Map tierId (0|1|2) to Stripe Price ID env var
const TIER_PRICE_MAP: Record<number, string | undefined> = {
  0: process.env.STRIPE_PRICE_BASIC,
  1: process.env.STRIPE_PRICE_PRO,
  2: process.env.STRIPE_PRICE_ELITE,
};

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { tierId, walletAddress } = body as { tierId: 0 | 1 | 2; walletAddress?: string };

    if (tierId === undefined || ![0, 1, 2].includes(tierId)) {
      return NextResponse.json({ error: "Invalid tierId" }, { status: 400 });
    }

    const priceId = TIER_PRICE_MAP[tierId];
    if (!priceId) {
      return NextResponse.json(
        { error: "Stripe Price ID not configured for this tier" },
        { status: 500 }
      );
    }

    const tierNames = ["BASIC", "PRO", "ELITE"];
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: `${req.nextUrl.origin}/subscribe/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${req.nextUrl.origin}/subscribe`,
      customer_email: walletAddress ?? undefined,
      metadata: {
        tierId: String(tierId),
        tierName: tierNames[tierId],
        walletAddress: walletAddress ?? "",
      },
      subscription_data: {
        metadata: {
          tierId: String(tierId),
          walletAddress: walletAddress ?? "",
        },
      },
    });

    return NextResponse.json({ checkoutUrl: session.url });
  } catch (err) {
    console.error("[create-checkout]", err);
    const message = err instanceof Error ? err.message : "Internal server error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
