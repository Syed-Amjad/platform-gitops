#!/usr/bin/env bash
# ArgoCD, configured, then the root app-of-apps.
#
# After this script, git is the only deployment mechanism. Nothing else in the
# project is applied by hand.
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

log "Installing ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "Waiting for ArgoCD to come up"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s

# ---------------------------------------------------------------------------
# THE FLAG THAT SILENTLY BREAKS EVERYTHING IF MISSING.
#
# overlays/*/kustomization.yaml uses `helmCharts:` to render the Helm chart
# through Kustomize. Without --enable-helm, kustomize build produces NO output
# for those entries and reports no error — the Application syncs "successfully"
# and deploys nothing but the Services from base/.
# ---------------------------------------------------------------------------
log "Enabling the Helm renderer inside Kustomize"
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm"}}'

log "Restarting the repo server so it picks up the flag"
kubectl -n argocd rollout restart deploy/argocd-repo-server
kubectl -n argocd rollout status  deploy/argocd-repo-server --timeout=180s

log "Initial admin password"
PW="$(kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d)"
echo "    ${PW}"

cat <<EOF

==> ArgoCD is up.

Do these two things BEFORE you screenshot anything:

  1. Change the admin password
       kubectl port-forward svc/argocd-server -n argocd 8080:443 &
       argocd login localhost:8080 --username admin --password '${PW}' --insecure
       argocd account update-password

  2. Delete the bootstrap secret, which still holds the old one
       kubectl -n argocd delete secret argocd-initial-admin-secret

Then apply the root app — the only manual kubectl apply in the whole project:

  kubectl apply -f argocd/projects/platform.yaml
  kubectl apply -f argocd/root-app.yaml

Watch the waves land in order:

  watch -n2 'kubectl -n argocd get applications'
EOF
