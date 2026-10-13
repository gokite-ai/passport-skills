#!/usr/bin/env bash
set -euo pipefail

# Set the installer base URL based on environment (prod, staging, or --check)
# Usage: bash set-installer-base.sh [prod|staging|--check] [repo_root]
#
# Arguments:
#   First arg (optional): environment (prod, staging) or --check
#     - If not provided, uses INSTALLER_ENV environment variable
#     - If INSTALLER_ENV is empty, unset, or "prod", writes https://cli.gokite.ai
#     - If "staging", writes https://cli.staging.gokite.ai
#     - If "--check", validates that .installer-base contains the prod URL
#     - Any other value: prints error and exits 1
#   Second arg (optional): repository root (default: parent of script directory)

ENV="${1:-${INSTALLER_ENV:-}}"
REPO_ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALLER_BASE_FILE="$REPO_ROOT/.installer-base"

PROD_URL="https://cli.gokite.ai"
STAGING_URL="https://cli.staging.gokite.ai"

if [[ "$ENV" == "--check" ]]; then
  if [[ -f "$INSTALLER_BASE_FILE" ]]; then
    current="$(tr -d '[:space:]' < "$INSTALLER_BASE_FILE" 2>/dev/null)"
    if [[ "$current" == "$PROD_URL" ]]; then
      echo "installer base ok"
      exit 0
    else
      echo "installer base is not prod: $current" >&2
      exit 1
    fi
  else
    echo "installer base is not prod: file missing" >&2
    exit 1
  fi
fi

if [[ -z "$ENV" || "$ENV" == "prod" ]]; then
  printf '%s' "$PROD_URL" > "$INSTALLER_BASE_FILE"
elif [[ "$ENV" == "staging" ]]; then
  printf '%s' "$STAGING_URL" > "$INSTALLER_BASE_FILE"
else
  echo "bad INSTALLER_ENV: $ENV" >&2
  exit 1
fi
