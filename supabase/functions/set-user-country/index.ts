// supabase/functions/set-user-country/index.ts
// Edge Function triggered on user login to store country code in app_metadata.
// Country is read from x-vercel-ip-country header (set automatically by Vercel).
Deno.serve(async (req) => {
  const { user } = await req.json();

  if (!user?.id) {
    return new Response(JSON.stringify({ error: 'Missing user' }), { status: 400 });
  }

  const country = req.headers.get('x-vercel-ip-country') ||
    req.headers.get('cf-ipcountry') ||
    'XX';

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const updateRes = await fetch(`${supabaseUrl}/auth/v1/admin/users/${user.id}`, {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
      'apikey': serviceRoleKey,
    },
    body: JSON.stringify({
      app_metadata: {
        ...user.app_metadata,
        country: country.toUpperCase(),
        country_set_at: new Date().toISOString(),
      },
    }),
  });

  if (!updateRes.ok) {
    const err = await updateRes.text();
    console.error('[set-user-country] update failed:', err);
    return new Response(JSON.stringify({ error: 'Failed to update user country' }), { status: 500 });
  }

  return new Response(JSON.stringify({ success: true, country: country.toUpperCase() }));
});
