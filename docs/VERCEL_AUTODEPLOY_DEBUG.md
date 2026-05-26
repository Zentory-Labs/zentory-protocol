# Vercel auto-deploy keeps regressing (#108)

Push to `main` should trigger a Vercel production deploy automatically.
It does for the marketing site (`zentorylabs.com` Vercel project). It
**intermittently** doesn't for the dApp (`zentory-token` Vercel project).

Seen twice in this session: commits `c79796c` and `cdbe78e` both required
manual `vercel --prod --yes` to actually ship. The deploys 13h apart in
`vercel ls` output are the gap.

## Likely causes (in order of probability)

### 1. Vercel GitHub App is scoped to specific repos and `zentory-app` access is intermittent

Check at https://github.com/settings/installations → find Vercel →
Configure → confirm `Zentory-Labs/zentory-app` is in the "Repository
access" list. If it shows as "Selected repositories", make sure the dApp
repo is selected. If it's not, GitHub silently drops webhooks for
unselected repos.

### 2. Production branch is set to something other than `main`

Vercel project → Settings → Git → Production Branch. Should be `main`.
If it was changed to `master` or `production` at some point, pushes to
`main` won't deploy.

### 3. Vercel webhook delivery is failing on the GitHub side

At https://github.com/Zentory-Labs/zentory-app/settings/hooks → find the
Vercel webhook → "Recent Deliveries" tab. Look for red X marks. If
webhook delivery is failing (404, 500, timeout), that's the bug. Click
"Redeliver" on a failed event to retry.

### 4. "Ignored Build Step" set to `exit 0`

Vercel project → Settings → Git → "Ignored Build Step" command. If
someone set this to `exit 0` (which skips ALL builds), every push is
silently skipped. Should be empty or a real conditional check.

## What I tried in this session

For both commits that didn't auto-deploy, running `vercel --prod --yes`
from the project root manually triggered a deploy that completed
successfully. So the build pipeline itself is fine — only the
push → trigger handoff is broken.

## How to verify the fix is in place

After applying any of the fixes above:

1. Make a trivial change in the repo (e.g. add a space to a comment)
2. `git commit -am "test: verify auto-deploy" && git push`
3. Within 60 seconds, check Vercel → Deployments. A new "Building"
   deployment should appear, source = git push, ref = `main`, commit =
   your new SHA.
4. If nothing appears, check GitHub webhook deliveries (#3 above).

## Permanent workaround

If auto-deploy stays flaky, add a GitHub Action that pings Vercel's
deploy webhook on push:

```yaml
# .github/workflows/vercel-deploy.yml
on: { push: { branches: [main] } }
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          curl -X POST \
            -H "Authorization: Bearer ${{ secrets.VERCEL_TOKEN }}" \
            "https://api.vercel.com/v13/deployments?projectId=${{ secrets.VERCEL_PROJECT_ID }}"
```

This bypasses Vercel's own GitHub integration entirely. Needs:
- `VERCEL_TOKEN` (Vercel → Account Settings → Tokens, scope to the project)
- `VERCEL_PROJECT_ID` (Vercel project → Settings → General → Project ID)

I'd hold off on this until you confirm the GitHub App config is fine. The
fallback is more code to maintain.

---

*Last updated: 2026-05-25. Tracked as task #108.*
