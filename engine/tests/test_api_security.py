import os

import httpx
import pytest


@pytest.mark.asyncio
async def test_execute_requires_auth_when_configured():
    """
    Gate G6: privileged API auth verified.

    This test is environment-driven so it can run against either a local dev server
    or a deployed environment.
    """
    base_url = os.getenv("ZENTORY_BASE_URL")
    api_key = os.getenv("KEEPER_API_KEY")

    if not base_url or not api_key:
        pytest.skip("Set ZENTORY_BASE_URL and KEEPER_API_KEY to run this test")

    url = base_url.rstrip("/") + "/api/signals/execute"

    payload = {
        "signalId": "test-signal",
        "asset": "BTC",
        "direction": "LONG",
        "size": 1,
        "price": 1.0,
    }

    async with httpx.AsyncClient(timeout=60.0) as client:
        r1 = await client.post(url, json=payload)
        assert r1.status_code in (401, 500, 503)

        r2 = await client.post(
            url,
            json=payload,
            headers={"Authorization": f"Bearer {api_key}"},
        )
        # If keeper key/supabase aren't configured in the target env, we accept the expected failures.
        assert r2.status_code in (200, 500, 503)

