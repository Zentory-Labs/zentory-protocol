# Geo-Blocking Implementation Guide

> **Status:** Implementation-Ready
> **Last Updated:** 2026-04-30
> **Stack:** Next.js 16 (App Router) · Supabase · Vercel Edge

---

## 1. Recommended Geo-IP Service

### Recommendation: **MaxMind GeoIP2** (Self-Hosted Database)

For a Web3/DeFi application with compliance requirements, MaxMind GeoIP2 is the best choice.

#### Why MaxMind over IPinfo or IPGeolocation.io

| Criteria | MaxMind GeoIP2 | IPinfo | IPGeolocation.io |
|---|---|---|---|
| **Pricing** | $22/mo (Country DB) · $66/mo (City DB) · $0.0001/query (web service) | $49/mo entry | $15/mo entry |
| **Country accuracy** | **99.8%** (published) | ~99.5% (CDN benchmark) | ~99% |
| **City accuracy** | ~66% (50km radius) / web svc +2-5% | ~93% (CDN benchmark) | ~70-80% |
| **Self-hosted DB** | ✅ mmdb file, zero per-query cost | ❌ API only | ✅ DB available |
| **VPN/Proxy detection** | Separate product (minFraud) | Privacy flags in paid tier | ✅ Security API |
| **Compliance** | EU data residency options, B2B clarity | No published EU options | Limited |
| **Update frequency** | Weekly (database) / Real-time (web svc) | Daily | Daily |
| **Free tier** | GeoLite2 (limited accuracy) | 50K req/mo (country only) | 1K/day |

#### For ZENTORY Labs specifically

Given that you need **SSR blocking before render** (not just API enrichment), the self-hosted database model is ideal:

1. **No per-query API cost** — the DB is downloaded and queried locally
2. **No network latency** — lookup is a local file read
3. **Vercel Edge compatible** — GeoIP2 mmdb files can be deployed to Edge Runtime
4. **Regulatory defensibility** — documented, auditable, widely used in compliance systems

#### How to get started

```bash
# 1. Create a MaxMind account at https://www.maxmind.com
# 2. Download GeoLite2 Country or GeoIP2 Country mmdb
# 3. Use the `maxmind` npm package in middleware

npm install maxmind
```

**Alternative for lighter weight:** Use the free **GeoLite2 Country** database (weekly updates) via the `maxmind` package. Accuracy is lower than paid GeoIP2 but country-level blocking only requires 99.8% accuracy — which GeoLite2 provides.

> **Note on IPinfo:** If you prefer a managed API with the best city-level accuracy (93%), IPinfo is the next best option. Its privacy flags (VPN/proxy detection) are valuable for DeFi compliance. Use IPinfo.io Core ($49/mo) for country-level lookups with fallback VPN detection via their API.

---

## 2. Implementation Architecture

### Overview

```
Request arrives
      │
      ▼
┌─────────────────────────────┐
│  Next.js Edge Middleware    │  ← First line of defense
│  (middleware.ts)            │    Runs at Edge, before render
└──────────┬──────────────────┘
           │
    ┌──────┴──────┐
    │  Blocked?   │
    └──┬───────┬──┘
       │YES     │NO
       ▼        ▼
  /blocked    Continue
  page        │
               ▼
      ┌─────────────────────┐
      │  API Routes         │  ← Secondary enforcement
      │  (Route Handlers)   │    Check geo headers + Supabase
      └──────────┬──────────┘
                 │
                 ▼
      ┌─────────────────────┐
      │  Supabase RLS       │  ← Database-level enforcement
      │  (country in JWT)   │    Always enforced server-side
      └─────────────────────┘
```

### SSR Pages (Next.js App Router)

**Edge Middleware** (`middleware.ts` at project root):

- Runs at the **Edge** before any page renders — blocked users never download page JS
- Uses `x-vercel-ip-country` header (set automatically by Vercel) or `@vercel/functions` `geolocation()`
- Rewrite to `/blocked` instead of redirect — blocked users don't see URL change

**Limitations:**
- Geo headers only available on Vercel deployment, not locally
- VPN users bypass this layer (documented in Edge Cases)

### API Routes (Route Handlers)

**Every restricted API route** should:
1. Read `x-vercel-ip-country` header
2. Cross-check against a server-side blocklist
3. Return `451 Unavailable For Legal Reasons` if blocked

API routes are also matched by the middleware, but defense-in-depth is critical — never rely solely on middleware.

### Supabase RLS

- Store `country_code` in the user's `app_metadata` (admin-writable, not user-editable)
- Add country claim to JWT at login time via a Supabase Edge Function
- Use `auth.jwt() -> 'app_metadata' ->> 'country'` in RLS policies
- RLS is the **last line of defense** — enforced at the database level regardless of API

### Data Flow: Setting Country on Login

```
User authenticates
       │
       ▼
Supabase Auth → Edge Function trigger
       │
       ▼
Detect country from request headers (x-vercel-ip-country)
       │
       ▼
Update user app_metadata: { country: "US" }
       │
       ▼
Next auth token includes country in app_metadata JWT claim
       │
       ▼
Supabase RLS policies read country from JWT
```

---

## 3. Code Examples

### 3a. Next.js Edge Middleware

Place in `middleware.ts` at the **project root** (next to `package.json`).

```typescript
// middleware.ts
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { geolocation } from '@vercel/functions';

// ============================================================
// RESTRICTED COUNTRY LISTS
// ============================================================

/** Countries fully blocked (all products) — US + full-ban jurisdictions */
const FULL_BLOCKLIST = new Set([
  'US', // United States — all states
  // Add other full bans here (see Section 4 for full list)
]);

/**
 * EU countries requiring restrictions for specific asset classes.
 * Block for stocks/forex/commodities; allow for crypto (MiCA-compliant).
 * Add/remove based on which products are restricted per country.
 */
const EU_RESTRICTED = new Set([
  'AT', // Austria
  'BE', // Belgium
  'BG', // Bulgaria
  'HR', // Croatia
  'CY', // Cyprus
  'CZ', // Czech Republic
  'DK', // Denmark
  'EE', // Estonia
  'FI', // Finland
  'FR', // France
  'DE', // Germany
  'GR', // Greece
  'HU', // Hungary
  'IE', // Ireland
  'IT', // Italy
  'LV', // Latvia
  'LT', // Lithuania
  'LU', // Luxembourg
  'MT', // Malta
  'NL', // Netherlands
  'PL', // Poland
  'PT', // Portugal
  'RO', // Romania
  'SK', // Slovakia
  'SI', // Slovenia
  'ES', // Spain
  'SE', // Sweden
]);

/** Routes that are never blocked (legal pages, static assets) */
const ALLOWED_PATHS = new Set([
  '/blocked',
  '/legal',
  '/terms',
  '/privacy',
  '/favicon.ico',
]);

/** Routes requiring EU restriction (stocks/forex/commodities) */
const RESTRICTED_ASSET_ROUTES = new Set([
  '/markets',    //may include stock assets
  '/stake',      //may include commodity-linked products
  '/govern',     //governance participation
  '/subscribe',  //subscription products
]);

// ============================================================
// HELPER: Get country from request
// ============================================================

function getCountry(request: NextRequest): string | undefined {
  // Vercel automatically sets this header on all Edge requests
  return request.headers.get('x-vercel-ip-country') ||
    // Fallback to @vercel/functions helper
    geolocation(request).country;
}

// ============================================================
// MIDDLEWARE
// ============================================================

export default function middleware(request: NextRequest) {
  const pathname = request.nextUrl.pathname;

  // Always allow safe paths
  if (ALLOWED_PATHS.has(pathname)) {
    return NextResponse.next();
  }

  // Allow non-asset routes for most users
  const isRestrictedAssetRoute = RESTRICTED_ASSET_ROUTES.has(pathname);

  const country = getCountry(request) || '';
  const countryUpper = country.toUpperCase();

  // 1. Full blocklist — always blocked regardless of route
  if (FULL_BLOCKLIST.has(countryUpper)) {
    return NextResponse.rewrite(
      new URL('/blocked', request.url)
    );
  }

  // 2. EU restricted routes — block EU countries for restricted assets
  if (isRestrictedAssetRoute && EU_RESTRICTED.has(countryUpper)) {
    return NextResponse.rewrite(
      new URL('/blocked', request.url)
    );
  }

  // 3. Other restricted countries (per-product, per-country)
  //    Expand BLOCKED_COUNTRIES as regulatory requirements grow
  // const BLOCKED_COUNTRIES = new Set(['KP', 'IR', 'SY']); // sanctions lists
  // if (BLOCKED_COUNTRIES.has(countryUpper)) { ... }

  return NextResponse.next();
}

// ============================================================
// MATCHER: Which routes the middleware runs on
// ============================================================

export const config = {
  matcher: [
    // Skip Next.js internals and all static files
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|css|js|woff2?|ttf)).*)',
    // Always run on API routes (defense in depth)
    '/(api|app/api)(.*)',
    // Run on all app pages
    '/((?!blocked|legal|terms|privacy).*)',
  ],
};
```

### 3b. API Route Helper Function

```typescript
// lib/geo-blocking.ts

export interface GeoCheckResult {
  allowed: boolean;
  country?: string;
  reason?: 'FULL_BLOCKLIST' | 'EU_RESTRICTED_ASSET' | 'SANCTIONS';
}

/** Returns ISO 3166-1 alpha-2 country code from Vercel headers */
export function getCountryFromRequest(request: Request): string | undefined {
  return request.headers.get('x-vercel-ip-country') || undefined;
}

const FULL_BLOCKLIST = new Set(['US']);
const EU_RESTRICTED = new Set([
  'AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU',
  'IE','IT','LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE',
]);

/** RESTRICTED_ASSET_ROUTES should match your middleware config */
const RESTRICTED_ASSET_ROUTES = new Set(['/markets','/stake','/govern','/subscribe']);

export function checkGeoAccess(
  country: string | undefined,
  path: string
): GeoCheckResult {
  if (!country) {
    // No geo data — fail open or closed based on compliance tolerance
    // For financial products: fail closed (block by default)
    return { allowed: false, reason: 'FULL_BLOCKLIST' };
  }

  const c = country.toUpperCase();

  if (FULL_BLOCKLIST.has(c)) {
    return { allowed: false, country: c, reason: 'FULL_BLOCKLIST' };
  }

  const isRestrictedAsset = RESTRICTED_ASSET_ROUTES.has(path);
  if (isRestrictedAsset && EU_RESTRICTED.has(c)) {
    return { allowed: false, country: c, reason: 'EU_RESTRICTED_ASSET' };
  }

  return { allowed: true, country: c };
}

/** Apply this to every restricted API route */
export function geoBlockResponse(result: GeoCheckResult): Response | null {
  if (!result.allowed) {
    const messages: Record<string, string> = {
      FULL_BLOCKLIST: 'Access restricted. This product is not available in your region.',
      EU_RESTRICTED_ASSET: 'Access restricted. This asset class is not available in your country.',
      SANCTIONS: 'Access restricted due to regulatory requirements.',
    };
    return new Response(
      JSON.stringify({ error: 'geo_blocked', message: messages[result.reason!] }),
      {
        status: 451, // Unavailable For Legal Reasons
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
  return null;
}
```

**Usage in an API Route Handler:**

```typescript
// app/api/markets-signals/route.ts
import { NextRequest } from 'next/server';
import {
  getCountryFromRequest,
  checkGeoAccess,
  geoBlockResponse,
} from '@/lib/geo-blocking';

export async function GET(request: NextRequest) {
  const country = getCountryFromRequest(request);
  const path = request.nextUrl.pathname;

  const geoCheck = checkGeoAccess(country, path);
  const blocked = geoBlockResponse(geoCheck);
  if (blocked) return blocked;

  // ... continue with handler logic
}
```

### 3c. React Hook `useGeoBlocking()`

```typescript
// hooks/useGeoBlocking.ts
'use client';

import { useEffect, useState } from 'react';

export interface GeoInfo {
  country: string | null;
  isBlocked: boolean;
  isLoading: boolean;
  blockReason?: string;
}

/**
 * Client-side geo-blocking hook.
 * Reads country from a cookie set by the middleware.
 * Use for UI state only — never for security-critical logic.
 *
 * Security-critical blocking MUST happen in middleware + API routes + RLS.
 */
export function useGeoBlocking(): GeoInfo {
  const [geo, setGeo] = useState<GeoInfo>({
    country: null,
    isBlocked: false,
    isLoading: true,
  });

  useEffect(() => {
    // The middleware sets this cookie on blocked requests
    const blocked = document.cookie.includes('geo-blocked=true');
    const countryMatch = document.cookie.match(/geo-country=([^;]+)/);
    const country = countryMatch ? countryMatch[1] : null;
    const reasonMatch = document.cookie.match(/geo-block-reason=([^;]+)/);

    setGeo({
      country,
      isBlocked: blocked,
      isLoading: false,
      blockReason: reasonMatch ? reasonMatch[1] : undefined,
    });
  }, []);

  return geo;
}
```

**Middleware sets the cookie** (add to your `middleware.ts`):

```typescript
// In the blocked response branch:
const blockedResponse = NextResponse.rewrite(new URL('/blocked', request.url));
blockedResponse.cookies.set('geo-blocked', 'true', {
  httpOnly: false,  // Allow client JS to read
  secure: true,
  sameSite: 'lax',
  maxAge: 60 * 60, // 1 hour
});
blockedResponse.cookies.set('geo-country', countryUpper, { same options });
blockedResponse.cookies.set('geo-block-reason', 'FULL_BLOCKLIST', { same options });
return blockedResponse;
```

**Usage in a component:**

```tsx
// components/ProtectedAssetRoute.tsx
'use client';

import { useGeoBlocking } from '@/hooks/useGeoBlocking';
import { useRouter } from 'next/navigation';

export function ProtectedAssetRoute({ children }: { children: React.ReactNode }) {
  const { isBlocked, isLoading, blockReason } = useGeoBlocking();
  const router = useRouter();

  useEffect(() => {
    if (isBlocked && !isLoading) {
      router.push('/blocked');
    }
  }, [isBlocked, isLoading, router]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand" />
      </div>
    );
  }

  if (isBlocked) return null;
  return <>{children}</>;
}
```

---

## 4. Restricted Country Lists

### ISO 3166-1 alpha-2 Country Codes

#### US (Full Blocklist)

The US requires **state-level awareness only for tax reporting**, not for geo-blocking. Block the entire US at the country level using `US`. Individual states do not have distinct ISO codes for geo-blocking purposes.

```
US — United States of America (all states: AL, AK, AZ, AR, CA, CO, CT, DE, FL, GA,
     HI, ID, IL, IN, IA, KS, KY, LA, ME, MD, MA, MI, MN, MS, MO, MT, NE, NV, NH,
     NJ, NM, NY, NC, ND, OH, OK, OR, PA, RI, SC, SD, TN, TX, UT, VT, VA, WA,
     WV, WI, WY, DC)
```

**US blocking rationale:** US securities law (SEC, FINRA) restricts stocks/forex/commodities. US users are fully blocked for restricted asset classes.

#### EU Countries Requiring Restrictions

These 27 EU member states require restrictions for stocks, forex, and commodities under MiFID II / national implementations:

```
AT, BE, BG, HR, CY, CZ, DK, EE, FI, FR, DE, GR, HU, IE, IT,
LV, LT, LU, MT, NL, PL, PT, RO, SK, SI, ES, SE
```

**EU blocking rationale:** Under MiFID II, retail clients in the EU have restricted access to complex derivatives (forex, CFDs, commodities). The exact restrictions vary by country but the default position should be block for restricted asset products.

> **Note:** EU blocking applies **only to restricted asset classes** (stocks via CFDs, forex, commodities). DeFi/crypto operations may be allowed under MiCA. Adjust your route-specific blocking accordingly.

#### Other Countries to Block (Sanctions & High-Risk)

These are blocked regardless of product:

```
KP — North Korea (full sanctions)
IR — Iran (full sanctions)
SY — Syria (full sanctions)
CU — Cuba (OFAC sanctions)
RU — Russia (OFAC sectoral sanctions — verify current requirements)
BY — Belarus (sanctions)
MM — Myanmar (coup-related sanctions)
VE — Venezuela (OFAC sanctions)
```

> **Compliance Note:** Sanctions lists change frequently. Subscribe to OFAC SDN updates and integrate a real-time sanctions screening service (e.g., Chainalysis, Elliptic) for financial applications. The above is a starting point, not legal advice.

#### Country-Specific Restrictions (Future Expansion)

As regulatory requirements grow, consider adding:

```
AU — Australia (ASIC restrictions on CFDs/forex)
NZ — New Zealand (FMA restrictions)
CA — Canada (IIROC provincial restrictions — QC, ON, BC specific)
SG — Singapore (MAS restrictions)
HK — Hong Kong (SFC restrictions)
```

---

## 5. Supabase Row Level Security

### Architecture

```
User record in auth.users
       │
       ▼
app_metadata.country set at login (via Edge Function)
       │
       ▼
Supabase JWT includes: { ..., "app_metadata": { "country": "DE" } }
       │
       ▼
RLS policy reads: auth.jwt() -> 'app_metadata' ->> 'country'
       │
       ▼
Policy enforces row-level access based on country
```

### Step 1: Set country on login (Edge Function)

Create `supabase/functions/set-user-country/index.ts`:

```typescript
Deno.serve(async (req) => {
  const { user } = await req.json();

  // Get country from request headers (set by Vercel)
  const country = req.headers.get('x-vercel-ip-country') || 'UNKNOWN';

  // Update app_metadata (admin-writable, not user-editable)
  const { data, error } = await supabase.auth.admin.updateUser(
    user.id,
    {
      app_metadata: {
        country,
        country_set_at: new Date().toISOString(),
      },
    }
  );

  if (error) return new Response(JSON.stringify({ error }), { status: 500 });
  return new Response(JSON.stringify({ success: true, country }));
});
```

**Trigger this from your middleware or a login API route** after `supabase.auth.signIn*` completes.

### Step 2: Add RLS policies

```sql
-- ============================================================
-- TABLE: user_portfolios
-- All users can only see their own rows by default
-- Plus: restricted_asset_rows only visible to non-blocked countries
-- ============================================================

-- 1. Enable RLS
ALTER TABLE user_portfolios ENABLE ROW LEVEL SECURITY;

-- 2. Users can only read their own rows
CREATE POLICY "users_read_own_portfolios"
  ON user_portfolios
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    AND (
      -- Allow non-restricted countries to see restricted assets
      (auth.jwt() -> 'app_metadata' ->> 'country') NOT IN ('US')
      OR
      -- Allow US users only for non-restricted asset types
      (asset_type != 'restricted')
    )
  );

-- 3. Insert policy
CREATE POLICY "users_insert_own_portfolios"
  ON user_portfolios
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND (auth.jwt() -> 'app_metadata' ->> 'country') != 'US'
  );

-- 4. Update only own rows
CREATE POLICY "users_update_own_portfolios"
  ON user_portfolios
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
```

### Step 3: For Restricted Asset Tables (Stocks/Forex/Commodities)

```sql
-- ============================================================
-- TABLE: restricted_asset_positions
-- Blocked entirely for US + EU users
-- ============================================================

CREATE POLICY "block_restricted_countries_from_assets"
  ON restricted_asset_positions
  FOR ALL
  TO authenticated
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'country') NOT IN (
      'US',
      'AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU',
      'IE','IT','LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE'
    )
  );
```

### JWT Refresh Note

> **Important:** When you update `app_metadata.country`, the user's existing JWT does not automatically reflect the change. The JWT is refreshed on the next `signIn` or when the token expires. For immediate enforcement, consider:
> 1. Short JWT expiry (e.g., 1 hour for sensitive financial apps)
> 2. A server-side check in your API routes (not just RLS) that re-fetches user metadata before sensitive operations

---

## 6. Edge Cases

### VPN Users

**Reality:** You cannot fully block VPN users. Sophisticated users will always be able to bypass geo-restrictions.

**Mitigations:**

1. **Combine with wallet-based checks** — if a wallet is associated with a blocked-region IP at signup, flag the account
2. **Proxy/VPN detection services** — use IPinfo Privacy Flags or IPGeolocation.io Security API to detect VPN/proxy/Tor exits. Block requests flagged as VPN/proxy for financial product routes:
   ```typescript
   // In your API route, before processing financial data:
   const vpnCheck = await fetch(`https://ipinfo.io/${ip}/privacy`, {
     headers: { Authorization: `Bearer ${process.env.IPINFO_TOKEN}` }
   });
   const { privacy } = await vpnCheck.json();
   if (privacy?.vpn || privacy?.proxy || privacy?.tor) {
     return new Response(JSON.stringify({ error: 'vpn_detected' }), { status: 403 });
   }
   ```
3. **Behavior-based risk scoring** — multiple accounts from same IP, rapid position changes, etc.
4. **Legal disclaimer** — include in Terms of Service that using VPNs to bypass restrictions is a violation and may result in account termination

**Documented limitation:** Any geo-blocking system can be bypassed by a motivated user with a VPN. Geo-blocking is a compliance hurdle, not a cryptographic guarantee. The goal is to deter casual access and establish a documented compliance effort.

### What to Show Blocked Users

**Legal basis for HTTP 451:** RFC 7725 (2015) — "Unavailable For Legal Reasons". Use this status code for blocked pages as it signals legal compliance rather than a technical error.

**`/blocked` page design:**

```tsx
// app/blocked/page.tsx
export default function BlockedPage() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-zinc-950 text-white px-6">
      <div className="max-w-lg text-center space-y-6">
        {/* 451 status */}
        <div className="text-8xl font-mono text-zinc-700 font-bold">451</div>

        <h1 className="text-3xl font-semibold">
          Access Restricted in Your Region
        </h1>

        <p className="text-zinc-400 text-lg leading-relaxed">
          We're sorry, but <strong className="text-white">this product is not available
          in your country or region</strong> due to regulatory requirements.
          This decision was made in accordance with applicable securities and
          derivatives legislation.
        </p>

        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-5 text-left">
          <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wide mb-3">
            What this means
          </h2>
          <ul className="space-y-2 text-sm text-zinc-300">
            <li className="flex gap-2">
              <span className="text-zinc-600">—</span>
              Applicable laws in your jurisdiction prohibit this product
            </li>
            <li className="flex gap-2">
              <span className="text-zinc-600">—</span>
              This restriction applies to all users in your region
            </li>
            <li className="flex gap-2">
              <span className="text-zinc-600">—</span>
              VPN usage to bypass this restriction is a Terms of Service violation
            </li>
          </ul>
        </div>

        <p className="text-zinc-500 text-sm">
          If you believe you are seeing this in error, contact support with your
          region details. Do not attempt to bypass this restriction.
        </p>

        <a
          href="/"
          className="inline-block px-6 py-3 bg-white text-black font-medium rounded-lg
                     hover:bg-zinc-200 transition-colors"
        >
          Return to Home
        </a>
      </div>
    </div>
  );
}
```

**Critical content to include in the blocked page:**
- Clear statement that the product is unavailable in their region
- Reference to "regulatory requirements" or "applicable law" (establishes good faith)
- **Do NOT** explain how to bypass the block (VPN disclaimer)
- **Do NOT** offer to escalate or manually approve bypass requests for restricted assets
- Contact info only for general inquiries, not for "unblock my region" requests

### Testing Locally

Geo headers are not set locally. To test:

```typescript
// middleware.ts — add mock for local development
function getCountry(request: NextRequest): string | undefined {
  if (process.env.NODE_ENV === 'development') {
    return process.env.MOCK_GEO_COUNTRY; // Set MOCK_GEO_COUNTRY=US in .env.local
  }
  return request.headers.get('x-vercel-ip-country') || undefined;
}
```

```bash
# .env.local
MOCK_GEO_COUNTRY=US
```

For CI/testing with Playwright, use Vercel CLI's `--dev` flag or mock the header via a test request header:

```typescript
// In your Playwright tests:
await page.request.headers({
  'x-vercel-ip-country': 'DE', // Simulate Germany
});
```

---

## Quick Reference

### Files to Create

| File | Purpose |
|---|---|
| `middleware.ts` | Edge geo-blocking (first line of defense) |
| `lib/geo-blocking.ts` | API route helper + `checkGeoAccess()` |
| `hooks/useGeoBlocking.ts` | Client-side hook for UI state |
| `app/blocked/page.tsx` | Blocked user page (HTTP 451) |
| `supabase/functions/set-user-country/index.ts` | Set country in app_metadata on login |
| `supabase/migrations/xxx_geo_rls.sql` | RLS policies for restricted tables |

### Environment Variables

```bash
# MaxMind GeoIP2 (self-hosted, no per-query cost)
MAXMIND_LICENSE_KEY=your_license_key

# IPinfo (if using managed API instead)
IPINFO_TOKEN=your_ipinfo_token

# Supabase Edge Function (if using IPinfo API for VPN detection)
IPINFO_TOKEN=your_ipinfo_token
```

### Key Implementation Checklist

- [ ] Deploy `middleware.ts` to Vercel
- [ ] Add `lib/geo-blocking.ts` and integrate into all restricted API routes
- [ ] Create `/blocked` page with HTTP 451 status
- [ ] Create `set-user-country` Edge Function
- [ ] Trigger country set on login flow
- [ ] Add RLS policies to restricted tables
- [ ] Test blocked page with `MOCK_GEO_COUNTRY=US`
- [ ] Test EU blocking with `MOCK_GEO_COUNTRY=DE`
- [ ] Add VPN/proxy detection to API routes
- [ ] Document compliance rationale in regulatory memo
- [ ] Review blocked country lists quarterly (regulations change)

---

## References

- [Vercel Geo-IP Headers](https://vercel.com/kb/guide/geo-ip-headers-geolocation-vercel-functions)
- [Vercel Geo-Blocking Example](https://github.com/vercel/examples/tree/main/edge-middleware/geolocation-country-block)
- [Supabase RLS + auth.jwt()](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [MaxMind GeoIP2 Documentation](https://dev.maxmind.com/geoip/docs)
- [RFC 7725 — HTTP 451](https://www.rfc-editor.org/rfc/rfc7725)
- [MiFID II Product Classification](https://www.esma.europa.eu/en/system/files/library/2015/11/10_06_04_mifid_ii_factsheet_retail_complex_products_en.pdf)
