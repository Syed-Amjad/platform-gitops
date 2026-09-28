#!/usr/bin/env bash
# Every UI at once. Ctrl-C stops them all.
#
# On an EC2 box, tunnel from your laptop rather than opening these ports in the
# security group:
#   ssh -L 8080:localhost:8080 -L 3000:localhost:3000 -L 9090:localhost:9090 \
#       -L 9093:localhost:9093 -L 20001:localhost:20001 ubuntu@<IP>
set -euo pipefail

pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

fwd() {
  echo "    $4  →  $1/$2"
  kubectl -n "$1" port-forward "svc/$2" "$3" >/dev/null 2>&1 &
  pids+=($!)
}

echo "==> Forwarding:"
fwd argocd        argocd-server                          8080:443   "http://localhost:8080  ArgoCD"
fwd observability kube-prometheus-stack-grafana          3000:80    "http://localhost:3000  Grafana"
fwd observability kube-prometheus-stack-prometheus       9090:9090  "http://localhost:9090  Prometheus"
fwd observability kube-prometheus-stack-alertmanager     9093:9093  "http://localhost:9093  Alertmanager"
fwd istio-system  kiali                                  20001:20001 "http://localhost:20001 Kiali"

echo
echo "Grafana admin password (from Vault via External Secrets):"
kubectl -n observability get secret grafana-admin \
  -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "  (not synced yet)"
echo
echo
echo "Ctrl-C to stop."
wait
