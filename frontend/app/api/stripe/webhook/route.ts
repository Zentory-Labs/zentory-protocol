import { NextRequest, NextResponse } from "next/server";
import { stripe } from "@/lib/stripe";
import { createClient } from "@/utils/supabase/server";

export const runtime = "nodejs";

export async function POST(req: NextRequest) {
  const rawBody = await req.text();
  const signature = req.headers.get("stripe-signature");

  if (!signature) {
    return NextResponse.json({ error: "Missing stripe-signature header" }, { status: 400 });
  }

  if (!process.env.STRIPE_WEBHOOK_SECRET) {
    console.error("[webhook] STRIPE_WEBHOOK_SECRET not set");
    return NextResponse.json({ error: "Webhook secret not configured" }, { status: 500 });
  }

  let event;
  try {
    event = stripe.webhooks.constructEvent(rawBody, signature, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error("[webhook] Signature verification failed:", err);
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  const supabase = await createClient();

  // ── checkout.session.completed ─────────────────────────────────────────────
  if (event.type === "checkout.session.completed") {
    const session = event.data.object as {
      metadata?: { tierId?: string; walletAddress?: string };
      id: string;
    };

    const tierId = session.metadata?.tierId;
    const walletAddress = session.metadata?.walletAddress;

    if (!tierId || ![0, 1, 2].includes(Number(tierId))) {
      console.warn("[webhook] checkout.session.completed: missing or invalid tierId", session.id);
      return NextResponse.json({ received: true });
    }

    // Idempotency: skip if this session_id was already processed
    const { data: existing } = await supabase
      .from("webhook_events")
      .select("id")
      .eq("stripe_event_id", session.id)
      .single();

    if (existing) {
      return NextResponse.json({ received: true });
    }

    // Record webhook event first (idempotency guard)
    await supabase.from("webhook_events").insert({
      stripe_event_id: session.id,
      event_type: "checkout.session.completed",
    });

    if (walletAddress) {
      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + 30);

      await supabase.from("subscriptions").insert({
        wallet_address: walletAddress.toLowerCase(),
        tier_id: Number(tierId),
        stripe_session_id: session.id,
        status: "active",
        expires_at: expiresAt.toISOString(),
      });

      await supabase.from("subscription_events").insert({
        wallet_address: walletAddress.toLowerCase(),
        tier_id: Number(tierId),
        event_type: "created",
        stripe_session_id: session.id,
      });
    }

    return NextResponse.json({ received: true });
  }

  // ── customer.subscription.deleted ──────────────────────────────────────────
  if (event.type === "customer.subscription.deleted") {
    const sub = event.data.object as { id: string; metadata?: { walletAddress?: string } };
    const walletAddress = sub.metadata?.walletAddress;

    await supabase
      .from("subscriptions")
      .update({ status: "cancelled" })
      .eq("stripe_session_id", sub.id);

    if (walletAddress) {
      await supabase.from("subscription_events").insert({
        wallet_address: walletAddress.toLowerCase(),
        tier_id: 0,
        event_type: "cancelled",
        stripe_session_id: sub.id,
      });
    }

    return NextResponse.json({ received: true });
  }

  // Acknowledge unhandled events so Stripe doesn't retry
  console.info(`[webhook] Unhandled event type: ${event.type}`);
  return NextResponse.json({ received: true });
}
