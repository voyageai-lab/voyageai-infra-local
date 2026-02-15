#!/usr/bin/env bash
# =============================================================================
# VoyageAI — Deploy to kind (Kubernetes in Docker)
# =============================================================================
# Usage:
#   ./k8s/deploy-kind.sh            # full deploy (create cluster + build + apply)
#   ./k8s/deploy-kind.sh --apply    # skip cluster creation & image build, only apply manifests
#   ./k8s/deploy-kind.sh --build    # only rebuild images and reload into kind
#
# Prerequisites:
#   - docker
#   - kind   (https://kind.sigs.k8s.io/)
#   - kubectl
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="voyageai"
NAMESPACE="voyageai"

# Paths to sibling service repos
JAVA_BACKEND_DIR="$INFRA_ROOT/../voyageai-backend"
PYTHON_SERVICE_DIR="$INFRA_ROOT/../voyageai-python-service"
FRONTEND_DIR="$INFRA_ROOT/../voyageai-web"

# Image names (must match k8s manifests)
JAVA_IMAGE="voyageai/java-backend:latest"
PYTHON_SVC_IMAGE="voyageai/python-service:latest"
PYTHON_WORKER_IMAGE="voyageai/python-worker:latest"
FRONTEND_IMAGE="voyageai/frontend:latest"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Pre-flight checks ────────────────────────────────────────
check_prerequisites() {
  for cmd in docker kind kubectl; do
    command -v "$cmd" >/dev/null 2>&1 || err "'$cmd' is not installed."
  done
  ok "Prerequisites: docker, kind, kubectl"
}

# ─── 1. Create kind cluster ───────────────────────────────────
create_cluster() {
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    info "kind cluster '${CLUSTER_NAME}' already exists, skipping creation."
  else
    info "Creating kind cluster '${CLUSTER_NAME}'..."
    kind create cluster \
      --name "$CLUSTER_NAME" \
      --config "$SCRIPT_DIR/kind-config.yaml"
    ok "Cluster created."
  fi
  kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 \
    || err "Cannot connect to cluster 'kind-${CLUSTER_NAME}'."
  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
}

# ─── 2. Install Nginx Ingress Controller ──────────────────────
install_ingress_controller() {
  if kubectl get ns ingress-nginx >/dev/null 2>&1; then
    info "Nginx Ingress Controller namespace exists, skipping install."
  else
    info "Installing Nginx Ingress Controller for kind..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    ok "Ingress controller manifests applied."
  fi

  info "Waiting for Ingress Controller to be ready (up to 120 s)..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s 2>/dev/null \
    || warn "Ingress controller not ready yet — it may take a moment."
}

# ─── 3. Build Docker images ───────────────────────────────────
build_images() {
  info "Building Docker images..."

  info "  -> Java Backend"
  docker build -t "$JAVA_IMAGE" \
    -f "$JAVA_BACKEND_DIR/Dockerfile" \
    "$JAVA_BACKEND_DIR" >/dev/null 2>&1

  info "  -> Python Service"
  docker build -t "$PYTHON_SVC_IMAGE" \
    -f "$PYTHON_SERVICE_DIR/Dockerfile" \
    "$PYTHON_SERVICE_DIR" >/dev/null 2>&1

  info "  -> Python Worker"
  docker build -t "$PYTHON_WORKER_IMAGE" \
    -f "$PYTHON_SERVICE_DIR/Dockerfile.worker" \
    "$PYTHON_SERVICE_DIR" >/dev/null 2>&1

  info "  -> Frontend"
  docker build -t "$FRONTEND_IMAGE" \
    -f "$FRONTEND_DIR/Dockerfile" \
    "$FRONTEND_DIR" >/dev/null 2>&1

  ok "All 4 images built."
}

# ─── 4. Load images into kind ─────────────────────────────────
load_images() {
  info "Loading images into kind cluster..."
  kind load docker-image "$JAVA_IMAGE"        --name "$CLUSTER_NAME" 2>/dev/null
  kind load docker-image "$PYTHON_SVC_IMAGE"  --name "$CLUSTER_NAME" 2>/dev/null
  kind load docker-image "$PYTHON_WORKER_IMAGE" --name "$CLUSTER_NAME" 2>/dev/null
  kind load docker-image "$FRONTEND_IMAGE"    --name "$CLUSTER_NAME" 2>/dev/null
  ok "Images loaded."
}

# ─── 5. Apply Kubernetes manifests ────────────────────────────
apply_manifests() {
  local base="$SCRIPT_DIR/base"

  info "Applying manifests..."

  # Namespace first
  kubectl apply -f "$base/namespace.yaml"

  # Secrets & Config
  kubectl apply -f "$base/secrets.yaml"
  kubectl apply -f "$base/configmap.yaml"

  # Infrastructure (order: Redis first, then MySQL, MongoDB, Kafka)
  kubectl apply -f "$base/redis.yaml"
  kubectl apply -f "$base/mysql.yaml"
  kubectl apply -f "$base/mongodb.yaml"
  kubectl apply -f "$base/kafka.yaml"

  # Wait for infra to be ready before starting app pods
  info "Waiting for infrastructure pods (up to 180 s)..."
  for sts in redis mysql mongodb kafka; do
    kubectl rollout status statefulset/"$sts" -n "$NAMESPACE" --timeout=180s 2>/dev/null \
      || warn "StatefulSet $sts not fully ready."
  done
  ok "Infrastructure ready."

  # Application pods
  kubectl apply -f "$base/java-backend.yaml"
  kubectl apply -f "$base/python-service.yaml"
  kubectl apply -f "$base/python-worker.yaml"
  kubectl apply -f "$base/frontend.yaml"

  # Ingress (last)
  kubectl apply -f "$base/ingress.yaml"

  ok "All manifests applied."
}

# ─── 6. Wait for everything ──────────────────────────────────
wait_for_pods() {
  info "Waiting for application pods to be ready (up to 300 s)..."
  for dep in java-backend python-service python-worker frontend; do
    kubectl rollout status deployment/"$dep" -n "$NAMESPACE" --timeout=300s 2>/dev/null \
      || warn "Deployment $dep not fully ready."
  done
  ok "All application pods ready."
}

# ─── 7. Print summary ────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}  VoyageAI deployed on kind!${NC}"
  echo -e "${GREEN}=============================================${NC}"
  echo ""
  echo -e "  URL:  ${CYAN}http://voyageai.local${NC}"
  echo ""
  echo -e "  ${YELLOW}Make sure /etc/hosts contains:${NC}"
  echo -e "    127.0.0.1  voyageai.local"
  echo ""
  echo -e "  Useful commands:"
  echo -e "    kubectl get pods -n $NAMESPACE"
  echo -e "    kubectl logs -n $NAMESPACE deployment/java-backend -f"
  echo -e "    kubectl logs -n $NAMESPACE deployment/python-worker -f"
  echo ""
  echo -e "  Teardown:"
  echo -e "    ./k8s/teardown-kind.sh"
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────
main() {
  local mode="${1:-full}"

  check_prerequisites

  case "$mode" in
    --apply)
      apply_manifests
      wait_for_pods
      print_summary
      ;;
    --build)
      build_images
      load_images
      ;;
    *)
      create_cluster
      install_ingress_controller
      build_images
      load_images
      apply_manifests
      wait_for_pods
      print_summary
      ;;
  esac
}

main "$@"
