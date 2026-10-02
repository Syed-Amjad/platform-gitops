#!/usr/bin/env bash
# ArgoCD, configured, then the root app-of-apps.
#
# After this script, git is the only deployment mechanism. Nothing else in the
# project is applied by hand.
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

log "Installing ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# --server-side IS REQUIRED, and the reason is the same one that forces
# ServerSideApply=true on the kube-prometheus-stack Application in
# argocd/applications/01-observability.yaml.
#
# Client-side apply records the entire manifest in the
# kubectl.kubernetes.io/last-applied-configuration annotation. ArgoCD's
# ApplicationSet CRD is larger than the 262144-byte ceiling for annotations, so
# a plain `kubectl apply` fails with:
#
#   The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
#   metadata.annotations: Too long: may not be more than 262144 bytes
#
# Server-side apply keeps field ownership in managedFields instead, with no such
# limit. --force-conflicts lets this reconcile a namespace where an earlier
# client-side apply already claimed some fields.
#
# This matters more than it looks: the failure aborts the script under
# `set -euo pipefail` BEFORE the kustomize --enable-helm patch below, which is
# the single most confusing misconfiguration in this whole repo.
# ---------------------------------------------------------------------------
kubectl apply -n argocd --server-side --force-conflicts -f \
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
