# Vercel Preview Deployments

## Setup

1. Connect the repo to Vercel: https://vercel.com/import
2. Add environment variables in Vercel dashboard → Settings → Environment Variables
3. For `KEEPER_PRIVATE_KEY` and other secrets: mark as "Secret"

## How it works

- Every PR gets a unique preview URL: `https://zentorytoken-{branch}.vercel.app`
- Production: only deployed when you manually promote a preview in Vercel dashboard
- Preview deployments auto-comment on the GitHub PR with the URL

## Required secrets in GitHub Actions

Add these to your GitHub repo → Settings → Secrets:

- `VERCEL_TOKEN` — Vercel personal access token
- `VERCEL_ORG_ID` — Found in Vercel dashboard → Settings → General
- `VERCEL_PROJECT_ID` — Found in Vercel dashboard → Settings → General

## Updating environment variables

Go to Vercel Dashboard → Your Project → Settings → Environment Variables.
Changes require a new deployment to take effect.
