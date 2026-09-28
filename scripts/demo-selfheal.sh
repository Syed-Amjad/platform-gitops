#!/usr/bin/env bash
# Demonstration 1 — reconciliation.
#
# Scale a live Deployment by hand and watch ArgoCD put it back to whatever git
# says. Record this: it is the shortest, clearest demo in the project.
#
# The framing that matters: this is usually described as a reliability feature.
# It is also a SECURITY control — an unauthorised change to production undoes
# itself, automatically, with nobody paged. Say exactly that when presenting it.
set -euo pipefail

NS="${NS:-webapp-prod}"
DEPLOY="${DEPLOY:-api-v1}"

declared() { kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.replicas}'; }

echo "==> Replicas declared in git, as currently applied: $(declared)"

echo "==> Scaling to 9 by hand — the thing nobody should ever do"
kubectl -n "$NS" scale deploy "$DEPLOY" --replicas=9
echo "    now: $(declared)"

echo "==> Watching for ArgoCD to revert it (up to 3 minutes)"
START=$(date +%s)
for _ in $(seq 1 90); do
  sleep 2
  R=$(declared)
  if [[ "$R" != "9" ]]; then
    echo
    echo "==> Reverted to ${R} after $(( $(date +%s) - START ))s."
    echo "    Nobody was paged. Nothing was approved. Git won."
    kubectl -n "$NS" get deploy "$DEPLOY"
    exit 0
  fi
  printf '.'
done

echo
echo "Still 9 after 3 minutes. Check that the Application has"
echo "  syncPolicy.automated.selfHeal: true"
echo "and that it is not showing a sync error:"
echo "  kubectl -n argocd get app webapp -o yaml | grep -A5 'status:'"
exit 1
