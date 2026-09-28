#!/usr/bin/env bash
# Demonstration 4 — make an alert actually fire.
#
# An alert you have never seen fire is a configuration, not an alert. This
# drives real 5xx through the app until the error-budget rule trips.
#
#   ./scripts/demo-alerts.sh errors     # drive WebappErrorBudgetBurn
#   ./scripts/demo-alerts.sh latency    # drive WebappLatencyHigh
#   ./scripts/demo-alerts.sh missing    # drive WebappTargetMissing
set -euo pipefail

MODE="${1:-errors}"
NS="${NS:-webapp-prod}"

GW_IP="$(kubectl -n istio-system get svc istio-ingressgateway \
          -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
[[ -z "$GW_IP" ]] && GW_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"

case "$MODE" in
  errors)
    echo "==> Driving 5xx for 12 minutes (the rule needs 'for: 10m')"
    echo "    Watch it go pending → firing in Prometheus → Alerts"
    END=$(( $(date +%s) + 720 ))
    while [[ $(date +%s) -lt $END ]]; do
      # 1 in 4 requests is an error — comfortably above the 1% threshold.
      curl -s -o /dev/null --max-time 3 "http://${GW_IP}/" || true
      curl -s -o /dev/null --max-time 3 \
        "http://api.${NS}.svc.cluster.local:8000/boom" 2>/dev/null || true
      kubectl -n "$NS" run curl-boom --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
        -s -o /dev/null "http://api.${NS}.svc.cluster.local:8000/boom" >/dev/null 2>&1 || true
      sleep 5
    done
    ;;

  latency)
    echo "==> Hitting /slow to push p99 past 1.5s"
    for _ in $(seq 1 200); do
      kubectl -n "$NS" run curl-slow --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
        -s -o /dev/null "http://api.${NS}.svc.cluster.local:8000/slow" >/dev/null 2>&1 || true
    done
    ;;

  missing)
    # The most instructive one. Deleting the ServiceMonitor does not break the
    # application at all — it breaks the ABILITY TO SEE the application. If no
    # alert fires here, your monitoring can fail silently and you would never
    # know, which is the exact failure this project is built to catch.
    echo "==> Deleting the api-v1 ServiceMonitor to simulate monitoring failure"
    echo "    (ArgoCD selfHeal will restore it — that is also worth recording)"
    kubectl -n "$NS" delete servicemonitor api-v1 || true
    echo "    Expect WebappTargetMissing or WebappNoTargetsDiscovered within ~10m."
    ;;

  *)
    echo "usage: $0 [errors|latency|missing]" >&2
    exit 1
    ;;
esac

cat <<'EOF'

Check the alert state:
  kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090 &
  open http://localhost:9090/alerts

And in Alertmanager, confirm severity routing and the inhibit rule:
  kubectl -n observability port-forward svc/kube-prometheus-stack-alertmanager 9093 &
  open http://localhost:9093
EOF
