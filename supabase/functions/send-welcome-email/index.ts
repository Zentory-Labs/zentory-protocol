// Supabase Edge Function: send-welcome-email
// Triggered by: database webhook on public.whitelist INSERT
// Env vars required: RESEND_API_KEY
//
// To enable: Supabase Dashboard → Database → Webhooks → CreateWebhook
//   Table: whitelist, Event: INSERT, Type: Database Webhook
//   HTTP Media Type: application/json
//   URL: https://<project-ref>.supabase.co/functions/v1/send-welcome-email

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "re_VSLYPSbd_HcQHtykLACL6NVdhPmnP861o";
const FROM_EMAIL = "Zentory Labs <onboarding@resend.dev>";
const SUBJECT = "Welcome to the Zentory Waitlist — here's what's coming.";

interface WhitelistPayload {
  type: "INSERT";
  table: "whitelist";
  record: {
    id: string;
    email: string;
    source: string;
    created_at: string;
  };
}

async function sendEmail(to: string): Promise<void> {
  const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Welcome to Zentory Labs</title>
  <!--[if mso]><style type="text/css">body, table, td {font-family: Arial, sans-serif !important;}</style><![endif]-->
</head>
<body style="margin: 0; padding: 0; background-color: #0b0b0d; font-family: 'Montserrat', Arial, sans-serif; -webkit-font-smoothing: antialiased;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #0b0b0d;">
    <tr>
      <td align="center" style="padding: 48px 16px;">

        <!-- Outer card -->
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
          style="max-width: 560px; background-color: #111114;
                 border-radius: 20px;
                 border: 1px solid rgba(255,255,255,0.08);
                 box-shadow: 0 32px 80px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.03) inset;
                 overflow: hidden;">

          <!-- Top gradient accent bar -->
          <tr>
            <td style="height: 3px; background: linear-gradient(90deg, #8b1e2d 0%, #c2353f 35%, #b08d57 65%, #8b1e2d 100%);"></td>
          </tr>

          <!-- Inner padding -->
          <tr>
            <td style="padding: 48px 48px 40px;">

              <!-- Logo area -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="padding-bottom: 36px;">
                    <!-- Logo image -->
                    <img src="https://zentorylabs.com/zentory_logo_light.png"
                         alt="Zentory Labs"
                         width="160"
                         style="display: block; outline: none; border: none; max-width: 100%;" />
                  </td>
                </tr>
              </table>

              <!-- Badge -->
              <table role="presentation" cellpadding="0" cellspacing="0" border="0"
                style="background: rgba(139,30,45,0.15); border: 1px solid rgba(139,30,45,0.3);
                       border-radius: 100px; display: inline-block; margin-bottom: 24px;">
                <tr>
                  <td style="padding: 6px 16px; font-size: 11px; font-weight: 700;
                             color: #c2353f; letter-spacing: 0.12em; text-transform: uppercase;
                             font-family: 'Montserrat', Arial, sans-serif;">
                    &#9679; &nbsp;Early Access — Limited Spots
                  </td>
                </tr>
              </table>

              <!-- Heading -->
              <div style="font-size: 30px; font-weight: 800; color: #ffffff;
                          line-height: 1.25; margin-bottom: 20px; letter-spacing: -0.02em;
                          font-family: 'Montserrat', Arial, sans-serif;">
                You&apos;re on the list. <br />
                <span style="background: linear-gradient(135deg, #c2353f, #e05a5a); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text;">
                  Here&apos;s what&apos;s coming.
                </span>
              </div>

              <!-- Body copy -->
              <div style="font-size: 15px; color: rgba(230,226,222,0.72); line-height: 1.75;
                          margin-bottom: 20px; font-family: 'Montserrat', Arial, sans-serif;">
                Thanks for joining the <strong style="color: #eaeaea; font-weight: 600;">Zentory waitlist</strong>.
                You&apos;re among the first to hear about our alpha vault launch,
                genetic programming signal feeds, and every protocol milestone — before the world does.
              </div>

              <div style="font-size: 15px; color: rgba(230,226,222,0.72); line-height: 1.75;
                          margin-bottom: 36px; font-family: 'Montserrat', Arial, sans-serif;">
                We&apos;ll send you early access, key updates, and everything in the pipeline.
                <strong style="color: #b08d57; font-weight: 600;">No spam — we promise.</strong>
              </div>

              <!-- Divider -->
              <div style="border-top: 1px solid rgba(255,255,255,0.07); margin-bottom: 32px;"></div>

              <!-- Feature pills -->
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom: 36px;">
                <tr>
                  <td style="padding: 12px 16px; background: rgba(139,30,45,0.08);
                             border: 1px solid rgba(139,30,45,0.2); border-radius: 10px;
                             width: 33%; text-align: center; vertical-align: middle;">
                    <div style="font-size: 11px; font-weight: 700; color: #c2353f;
                                text-transform: uppercase; letter-spacing: 0.08em;
                                font-family: 'Montserrat', Arial, sans-serif;">Alpha Vaults</div>
                  </td>
                  <td style="width: 8px;"></td>
                  <td style="padding: 12px 16px; background: rgba(176,141,87,0.08);
                             border: 1px solid rgba(176,141,87,0.2); border-radius: 10px;
                             width: 33%; text-align: center; vertical-align: middle;">
                    <div style="font-size: 11px; font-weight: 700; color: #b08d57;
                                text-transform: uppercase; letter-spacing: 0.08em;
                                font-family: 'Montserrat', Arial, sans-serif;">GP Signals</div>
                  </td>
                  <td style="width: 8px;"></td>
                  <td style="padding: 12px 16px; background: rgba(13,128,250,0.08);
                             border: 1px solid rgba(13,128,250,0.2); border-radius: 10px;
                             width: 33%; text-align: center; vertical-align: middle;">
                    <div style="font-size: 11px; font-weight: 700; color: #0d80fa;
                                text-transform: uppercase; letter-spacing: 0.08em;
                                font-family: 'Montserrat', Arial, sans-serif;">Early Access</div>
                  </td>
                </tr>
              </table>

              <!-- CTA Button -->
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td align="center" style="padding-bottom: 36px;">
                    <a href="https://zentorylabs.com"
                       style="display: inline-block; padding: 14px 36px;
                              background: linear-gradient(135deg, #8b1e2d, #c2353f);
                              color: #ffffff; font-size: 13px; font-weight: 700;
                              text-decoration: none; border-radius: 10px;
                              letter-spacing: 0.06em; text-transform: uppercase;
                              font-family: 'Montserrat', Arial, sans-serif;
                              box-shadow: 0 8px 24px rgba(139,30,45,0.4);">
                      Explore Zentory &rarr;
                    </a>
                  </td>
                </tr>
              </table>

              <!-- Footer -->
              <div style="border-top: 1px solid rgba(255,255,255,0.06); padding-top: 28px;">
                <div style="font-size: 11px; color: rgba(106,111,117,0.6); line-height: 1.7;
                            text-align: center; font-family: 'Montserrat', Arial, sans-serif;">
                  Zentory Labs &mdash; AI-driven alpha generation.<br/>
                  Built for transparency and risk-adjusted returns.<br/><br/>
                  <a href="https://zentorylabs.com"
                     style="color: #b08d57; text-decoration: none; font-weight: 600;">
                    zentorylabs.com
                  </a>
                  <br/><br/>
                  This email was sent because you signed up on our waitlist.<br/>
                  Not financial or legal advice.
                </div>
              </div>

            </td>
          </tr>

          <!-- Bottom gradient bar -->
          <tr>
            <td style="height: 2px; background: linear-gradient(90deg, #8b1e2d 0%, #c2353f 50%, #8b1e2d 100%);"></td>
          </tr>

        </table>
        <!-- /Outer card -->

      </td>
    </tr>
  </table>
</body>
</html>
`;

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [to],
      subject: SUBJECT,
      html,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Resend API error: ${response.status} ${text}`);
  }
}

serve(async (req: Request) => {
  let payload: WhitelistPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (payload.type !== "INSERT" || payload.table !== "whitelist") {
    return new Response(JSON.stringify({ error: "Unhandled event type" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const email = payload.record?.email;
  if (!email) {
    return new Response(JSON.stringify({ error: "No email in payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!RESEND_API_KEY) {
    console.warn("[send-welcome-email] RESEND_API_KEY not set — skipping email send");
    return new Response(JSON.stringify({ ok: true, skipped: true }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    await sendEmail(email);
    console.log(`[send-welcome-email] Sent welcome email to ${email}`);
    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[send-welcome-email] Failed to send email:", err);
    return new Response(JSON.stringify({ error: "Email send failed" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
