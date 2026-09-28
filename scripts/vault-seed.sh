#!/usr/bin/env bash
# Seed Vault with the demo secrets and wire up Kubernetes authentication.
#
# Nothing in this script's output belongs in git — that is the entire point of
# the layer it sets up.
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

VAULT_POD="vault-0"
NS="vault"
v() { kubectl exec -n "$NS" "$VAULT_POD" -- env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 "$@"; }

log "Waiting for Vault"
kubectl wait --for=condition=Ready pod/"$VAULT_POD" -n "$NS" --timeout=180s

log "Enabling Kubernetes auth"
v vault auth enable kubernetes 2>/dev/null || echo "    already enabled"

# Inside the pod, the API server address comes from the injected env vars.
v sh -c 'vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"'

log "Writing the policy"
# Read-only, and scoped to exactly two paths. An operator that can read every
# secret in Vault is not much better than a secret in git.
v sh -c 'vault policy write webapp - <<EOF
path "secret/data/webapp/*" {
  capabilities = ["read"]
}
path "secret/data/grafana/*" {
  capabilities = ["read"]
}
EOF'

log "Binding the policy to the External Secrets ServiceAccount"
v vault write auth/kubernetes/role/webapp \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=webapp \
  ttl=24h

log "Seeding secret values"
DB_PASS="$(openssl rand -base64 24)"
GF_PASS="$(openssl rand -base64 18)"

v vault kv put secret/webapp/database username=appuser password="$DB_PASS"
v vault kv put secret/grafana/admin  username=admin   password="$GF_PASS"

log "Verifying"
v vault kv get secret/webapp/database >/dev/null && echo "    webapp/database  OK"
v vault kv get secret/grafana/admin  >/dev/null && echo "    grafana/admin    OK"

cat <<EOF

==> Seeded.

Grafana admin password:  ${GF_PASS}

Note it now — it is regenerated on every run of this script, and Vault in dev
mode loses everything when the pod restarts. Both are lab-only behaviours and
both are stated in the README.

Next:  ./scripts/install-argocd.sh
EOF
