#!/usr/bin/env bash
# Demonstration 2 — measure the canary split.
#
# Sends N requests through the ingress gateway and counts which api version
# answered. With weights at 90/10 the result should land near 90/10 — and
# seeing the ACTUAL ratio, rather than asserting the configured one, is the
# difference between a demo and a measurement.
#
#   ./scripts/demo-canary.sh                 # 200 requests through the gateway
#   ./scripts/demo-canary.sh 500
#   CANARY_HEADER=1 ./scripts/demo-canary.sh # force v2 via the x-canary header
set -euo pipefail

N="${1:-200}"
NS="${NS:-webapp-prod}"

GW_IP="$(kubectl -n istio-system get svc istio-ingressgateway \
          -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
if [[ -z "$GW_IP" ]]; then
  # k3s ships servicelb, so the gateway usually gets the node IP. Fall back to it.
  GW_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
fi

URL="http://${GW_IP}/"
HDR=()
if [[ -n "${CANARY_HEADER:-}" ]]; then
  HDR=(-H "x-canary: true")
  echo "==> Sending x-canary: true — expecting 100% v2"
fi

echo "==> ${N} requests to ${URL}"
echo

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

for _ in $(seq 1 "$N"); do
  curl -s --max-time 3 "${HDR[@]}" "$URL" \
    | jq -r '.upstream.version // "ERROR"' >> "$TMP" || echo "ERROR" >> "$TMP"
done

echo "==> Responses by api version:"
sort "$TMP" | uniq -c | awk -v n="$N" '{printf "    %-8s %5d   %5.1f%%\n", $2, $1, ($1/n)*100}'

echo
echo "Configured weights, for comparison:"
kubectl -n "$NS" get virtualservice api -o jsonpath=\
'{range .spec.http[*].route[*]}    {.destination.subset}: {.weight}{"\n"}{end}' 2>/dev/null

cat <<'EOF'

To promote, edit istio/api-traffic.yaml in git — 90/10 → 50/50 → 0/100 — commit,
and let ArgoCD apply it. No kubectl. Re-run this script after each step and
record the measured ratio in docs/DEMO-RESULTS.md.
EOF
