#!/usr/bin/env bash
# Vault and External Secrets Operator.
#
# Installed with helm rather than managed by ArgoCD on purpose: ArgoCD's wave-0
# Application creates the ClusterSecretStore, which needs the ESO CRDs to exist
# already. Bootstrapping the thing that bootstraps your secrets is a chicken
# and egg you solve once, by hand, and then write down.
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# PINNED CHART VERSIONS.
#
# argocd/applications/01-observability.yaml already pins kube-prometheus-stack
# with the comment "an unpinned chart is an unreproducible cluster". That
# applied just as much here, and this script was not doing it — so the two
# things this project depends on most for its secrets story were floating on
# whatever upstream published that morning.
#
# ESO in particular does not tolerate floating: the 2.x CRDs serve ONLY v1,
# while 0.9.x–0.13.x served v1beta1. Whichever your manifests target, the chart
# version is what decides whether wave 0 syncs or fails with
# "no matches for kind ClusterSecretStore".
# ---------------------------------------------------------------------------
ESO_CHART_VERSION="${ESO_CHART_VERSION:-2.11.0}"
VAULT_CHART_VERSION="${VAULT_CHART_VERSION:-0.34.1}"

log "Installing Vault (DEV MODE — lab only)"
# ---------------------------------------------------------------------------
# Dev mode runs UNSEALED, IN-MEMORY, with a root token, and loses everything on
# restart. It is right for demonstrating the External Secrets pattern and wrong
# for anything else.
#
# Say this explicitly in your write-up. Claiming a production Vault deployment
# you did not do is the fastest way to fail a technical interview, and the
# honest version costs you nothing.
# ---------------------------------------------------------------------------
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
helm repo update -q
helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --version "$VAULT_CHART_VERSION" \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --set "injector.enabled=false" \
  --wait --timeout 5m

log "Installing External Secrets Operator"
# ---------------------------------------------------------------------------
# NOTE THE URL. The chart repository used to be charts.external-secrets.io.
# That host now 302-redirects and `helm repo add` against it fails outright:
#
#   Error: looks like "https://charts.external-secrets.io" is not a valid chart
#   repository or cannot be reached: ... context deadline exceeded
#
# The charts are served from the project's own domain now. This is the kind of
# breakage that has nothing to do with your configuration and costs twenty
# minutes anyway, because the error blames the repository rather than the move.
# ---------------------------------------------------------------------------
helm repo add external-secrets https://external-secrets.io --force-update
helm repo update -q
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --version "$ESO_CHART_VERSION" \
  --set installCRDs=true \
  --wait --timeout 5m

log "Waiting for the CRDs to register"
kubectl wait --for condition=established --timeout=90s \
  crd/clustersecretstores.external-secrets.io \
  crd/externalsecrets.external-secrets.io

echo
echo "External Secrets API versions served by this install:"
kubectl api-resources --api-group=external-secrets.io

cat <<'EOF'

==> Done.

The output above should show `v1` and NOT `v1beta1`. The manifests in secrets/
declare v1 to match ESO 2.x. If you pin an older ESO (0.9.x–0.13.x) those CRDs
serve v1beta1 instead and the three files in secrets/ must be changed back — a
mismatch surfaces as "no matches for kind ExternalSecret", which reads like a
typo and is not.

Next:  ./scripts/vault-seed.sh
EOF
