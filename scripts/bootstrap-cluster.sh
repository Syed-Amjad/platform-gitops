#!/usr/bin/env bash
# Cluster and mesh. Run once on a fresh t3.xlarge (16 GB).
#
# The full stack lands around 7.4 GB, so an 8 GB node fits it only until
# Prometheus grows — and leaves no room for the Zero-Trust layers that come
# next. Size once, build twice.
#
#   ./scripts/bootstrap-cluster.sh
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

log "Base packages"
sudo apt-get update -qq
sudo apt-get install -y -qq curl git jq apt-transport-https

log "Installing k3s"
# Traefik disabled — Istio's ingress gateway is the entry point here, and two
# ingress controllers fighting over :80 is a confusing first afternoon.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
export KUBECONFIG=~/.kube/config
grep -q 'KUBECONFIG' ~/.bashrc || echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl get nodes -o wide

log "Installing helm"
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

log "Installing istioctl"
if ! command -v istioctl >/dev/null; then
  curl -sL https://istio.io/downloadIstio | sh -
  sudo mv istio-*/bin/istioctl /usr/local/bin/
  rm -rf istio-*
fi

log "Installing the argocd CLI"
if ! command -v argocd >/dev/null; then
  curl -sSL -o /tmp/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x /tmp/argocd && sudo mv /tmp/argocd /usr/local/bin/argocd
fi

log "Installing Istio (demo profile)"
# The demo profile includes ingress and egress gateways plus generous telemetry
# — right for a lab. Use `default` or a trimmed profile in production.
istioctl install --set profile=demo -y

log "Installing Kiali and the Istio Grafana/Prometheus addons"
# Kiali renders the service graph and the live traffic split — it is what makes
# the canary visible rather than merely configured.
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/addons/kiali.yaml
kubectl -n istio-system rollout status deploy/kiali --timeout=180s || true

cat <<'EOF'

==> Cluster ready.

Next:
  ./scripts/install-platform-deps.sh   # Vault + External Secrets
  ./scripts/vault-seed.sh              # put the demo secrets into Vault
  ./scripts/install-argocd.sh          # ArgoCD, then the root app

Sanity check before continuing:
  kubectl get pods -n istio-system
  free -h        # expect ~2.5 GB used before ArgoCD and Prometheus arrive
EOF
