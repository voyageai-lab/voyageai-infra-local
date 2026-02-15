#!/usr/bin/env bash
# =============================================================================
# VoyageAI — Tear down kind cluster
# =============================================================================
# Usage:
#   ./k8s/teardown-kind.sh
#
# This deletes the entire kind cluster including all PVCs and data.
# The docker-compose environment is NOT affected.
# =============================================================================
set -euo pipefail

CLUSTER_NAME="voyageai"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if ! command -v kind >/dev/null 2>&1; then
  echo -e "${RED}[ERROR]${NC} 'kind' is not installed."
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo -e "${YELLOW}[WARN]${NC}  Cluster '${CLUSTER_NAME}' does not exist. Nothing to delete."
  exit 0
fi

echo -e "${YELLOW}[INFO]${NC}  Deleting kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "$CLUSTER_NAME"
echo -e "${GREEN}[OK]${NC}    Cluster '${CLUSTER_NAME}' deleted."
echo ""
echo "  docker-compose environment is unaffected."
echo "  To recreate: ./k8s/deploy-kind.sh"
