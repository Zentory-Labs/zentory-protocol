# Railway deployment health monitor

Railway cron services normally show `Exited` between scheduled runs, so the dashboard badge alone cannot distinguish a clean idle service from a failed deployment. The deployment health monitor in `.github/workflows/railway-health.yml` provides an explicit status view for the nine production services without turning advisory signals into failing CI.

## Operation

The workflow runs every 15 minutes and can also be started manually from **Actions → Railway health → Run workflow**. It queries Railway project `11ab73e0-e22e-406f-81eb-f410bafed818`, environment `5227fc35-5013-4e1b-b184-6f842412daa9`, then reports the latest deployment status for:

- `zentory-engine`
- `zent-indexer-executor`
- `Signal Indexer`
- `Spot Rebalance Direct`
- `Vault Nav indexer`
- `vigilant-wonder`
- `Zent Recorder`
- `zent-keeper-heartbeat`
- `zent-keeper-settle`

`RUNNING`, `SUCCESS`, `DEPLOYING`, `BUILDING`, `INITIALIZING`, and `SLEEPING` are healthy states. Any other state, a missing deployment, a missing service, or an API/network error produces a GitHub Actions warning annotation. The script always exits zero, so the workflow remains green while the warning and job summary retain the operational signal.

## Required secret

Create a Railway account or workspace token at https://railway.com/account/tokens with read access to project `11ab73e0-e22e-406f-81eb-f410bafed818`. In the `Zentory-Labs/zentory-protocol` repository, open **Settings → Secrets and variables → Actions → New repository secret** and create:

- Name: `RAILWAY_API_TOKEN`
- Value: the Railway token with project read access

The token is sent only in the Railway API authorization header. The script does not print it or dump Railway deployment objects.

## Reading a run

Each run includes a markdown table in the GitHub Actions job summary. Healthy services are labeled `Healthy`; suspicious or unavailable statuses are labeled `Warning` and also appear as yellow annotations while the run keeps a green check mark.
