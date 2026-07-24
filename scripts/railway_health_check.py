#!/usr/bin/env python3
"""Report Railway deployment health without failing GitHub Actions."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

API_URL = "https://backboard.railway.com/graphql/v2"
PROJECT_ID = "11ab73e0-e22e-406f-81eb-f410bafed818"
ENVIRONMENT_ID = "5227fc35-5013-4e1b-b184-6f842412daa9"
SERVICES = (
    "zentory-engine",
    "zent-indexer-executor",
    "Signal Indexer",
    "Spot Rebalance Direct",
    "Vault Nav indexer",
    "vigilant-wonder",
    "Zent Recorder",
    "zent-keeper-heartbeat",
    "zent-keeper-settle",
)
HEALTHY_STATES = {
    "RUNNING",
    "SUCCESS",
    "DEPLOYING",
    "BUILDING",
    "INITIALIZING",
    "SLEEPING",
}
QUERY = """
query RailwayHealth($projectId: String!) {
  project(id: $projectId) {
    name
    environments {
      nodes {
        id
        name
        services {
          edges {
            node {
              id
              name
              deployments {
                edges {
                  node {
                    id
                    status
                    createdAt
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
"""


def warn(message: str) -> None:
    safe_message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::warning file=railway-health.md::{safe_message}")


def write_summary(rows: list[tuple[str, str, str]]) -> None:
    lines = [
        "## Railway deployment health",
        "",
        f"Project `{PROJECT_ID}` · Environment `{ENVIRONMENT_ID}`",
        "",
        "| Service | Deployment status | Assessment |",
        "| --- | --- | --- |",
    ]
    for service, status, assessment in rows:
        lines.append(f"| {service} | `{status}` | {assessment} |")

    summary = "\n".join(lines) + "\n"
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with Path(summary_path).open("a", encoding="utf-8") as handle:
            handle.write(summary)
    else:
        print(summary)

    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with Path(output_path).open("a", encoding="utf-8") as handle:
            handle.write("summary<<RAILWAY_HEALTH_EOF\n")
            handle.write(summary)
            handle.write("RAILWAY_HEALTH_EOF\n")


def query_railway(token: str) -> dict[str, Any]:
    body = json.dumps(
        {"query": QUERY, "variables": {"projectId": PROJECT_ID}}
    ).encode("utf-8")
    request = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def collect_statuses(payload: dict[str, Any]) -> dict[str, str]:
    errors = payload.get("errors")
    if errors:
        messages = "; ".join(str(error.get("message", "unknown GraphQL error")) for error in errors)
        raise RuntimeError(messages)

    project = payload.get("data", {}).get("project")
    if not project:
        raise RuntimeError("Railway project was not returned")

    environments = project.get("environments", {}).get("nodes", [])
    environment = next(
        (item for item in environments if item.get("id") == ENVIRONMENT_ID),
        None,
    )
    if environment is None:
        raise RuntimeError(f"Railway environment {ENVIRONMENT_ID} was not returned")

    statuses: dict[str, str] = {}
    edges = environment.get("services", {}).get("edges", [])
    for edge in edges:
        service = edge.get("node") or {}
        name = service.get("name")
        if not name:
            continue
        deployments = [
            deployment_edge.get("node") or {}
            for deployment_edge in service.get("deployments", {}).get("edges", [])
        ]
        latest = max(deployments, key=lambda deployment: deployment.get("createdAt", ""), default={})
        statuses[name] = str(latest.get("status") or "NO_DEPLOY").upper()
    return statuses


def report(statuses: dict[str, str]) -> None:
    rows: list[tuple[str, str, str]] = []
    for service in SERVICES:
        status = statuses.get(service, "NO_DEPLOY")
        healthy = status in HEALTHY_STATES
        assessment = "Healthy" if healthy else "Warning"
        rows.append((service, status, assessment))
        print(f"{service}: {status}")
        if not healthy:
            warn(f"Service '{service}' status '{status}'")
    write_summary(rows)


def main() -> int:
    token = os.environ.get("RAILWAY_API_TOKEN", "").strip()
    if not token:
        warn("RAILWAY_API_TOKEN is not configured; Railway health could not be checked")
        write_summary([(service, "CHECK_FAILED", "Warning") for service in SERVICES])
        return 0

    try:
        report(collect_statuses(query_railway(token)))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, RuntimeError, KeyError, TypeError) as error:
        warn(f"Railway health check could not complete: {error}")
        write_summary([(service, "CHECK_FAILED", "Warning") for service in SERVICES])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        warn(f"Unexpected Railway health check error: {error}")
        sys.exit(0)
