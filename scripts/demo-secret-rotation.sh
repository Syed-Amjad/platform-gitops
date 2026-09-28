#!/usr/bin/env bash
# Demonstration 6 — rotate a credential in Vault and watch it reach the cluster
# with no commit, no pipeline run and no redeployment.
#
# This is the demo that proves the pattern rather than describing it.
set -euo pipefail

NS="${NS:-webapp-prod}"
SECRET="webapp-db"
v() { kubectl exec -n vault vault-0 -- env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 "$@"; }

current() {
  kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null | base64 -d
}

echo "==> Password currently in the Kubernetes Secret:"
echo "    $(current | cut -c1-8)…"

NEW="$(openssl rand -base64 24)"
echo
echo "==> Writing a new value into Vault"
v vault kv put secret/webapp/database username=appuser password="$NEW" >/dev/null
echo "    new value starts: $(echo "$NEW" | cut -c1-8)…"

echo
echo "==> Forcing an immediate refresh instead of waiting for refreshInterval (1h)"
# In production you wait. For a demo, annotating the ExternalSecret makes the
# operator reconcile now — the mechanism is identical, only the trigger differs.
kubectl -n "$NS" annotate externalsecret "$SECRET" \
  force-sync="$(date +%s)" --overwrite >/dev/null

echo "==> Waiting for the operator"
for _ in $(seq 1 30); do
  sleep 2
  if [[ "$(current)" == "$NEW" ]]; then
    echo
    echo "==> Secret updated in the cluster."
    kubectl -n "$NS" get externalsecret "$SECRET"
    cat <<'EOF'

What just happened, and why it matters:

  - The new value was never committed. Search this repo for it and you will
    find nothing — git holds the REFERENCE, not the secret.
  - No Deployment was updated, no pipeline ran, nobody approved a release.
  - Left alone, the same thing happens within refreshInterval on its own.

The pods still hold the OLD value in their environment, because envFrom is read
at container start. Restart them to pick it up:

  kubectl -n webapp-prod rollout restart deploy/api-v1 deploy/api-v2

Worth stating plainly in the write-up: External Secrets rotates the SECRET
automatically; making the APPLICATION pick it up without a restart needs either
a file mount with a watcher, or Reloader. Claiming zero-restart rotation without
that piece would be overclaiming.
EOF
    exit 0
  fi
  printf '.'
done

echo
echo "Secret did not update. Check the operator:"
echo "  kubectl -n webapp-prod describe externalsecret $SECRET"
echo "  kubectl -n external-secrets logs deploy/external-secrets"
exit 1
