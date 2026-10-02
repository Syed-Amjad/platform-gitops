#!/usr/bin/env bash
# Tear the lab down, and PROVE it is down.
#
# Run from your workstation (WSL), not from the box — the box is what this
# removes. Unlike the other scripts in this directory, which run on EC2.
#
#   ./scripts/lab-down.sh          # confirm, destroy, verify
#   ./scripts/lab-down.sh -y       # no confirmation prompt
#
# Nothing on the instance is worth keeping. k3s, Istio, ArgoCD, Vault and the
# applications were all installed from git by the other scripts here, so the box
# holds no state you cannot rebuild. Being able to destroy it on a whim is the
# argument for the whole architecture, not a cost-saving afterthought.
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }
err() { printf '\033[1;31m%s\033[0m\n' "$*"; }

REGION="${AWS_REGION:-us-east-1}"
TAG="gitops-observability-platform"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$HERE/terraform"
export AWS_PAGER=""

[[ -d "$TF_DIR" ]] || { err "No terraform directory at $TF_DIR"; exit 1; }
cd "$TF_DIR"

if [[ ! -f terraform.tfstate ]]; then
  warn "No terraform.tfstate here."
  warn "Either nothing was ever applied, or you are on a different machine from"
  warn "the one that applied it — state is local and gitignored by design."
  warn "Checking AWS directly anyway, because the bill does not care where the"
  warn "state file lives."
else
  log "Currently tracked in state"
  terraform state list | sed 's/^/    /' || true

  if [[ "${1:-}" != "-y" ]]; then
    echo
    read -r -p "Destroy all of the above? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { warn "Aborted. Nothing destroyed."; exit 0; }
  fi

  log "Destroying"
  terraform destroy -auto-approve
fi

# ---------------------------------------------------------------------------
# The part that actually matters.
#
# "terraform destroy completed" and "the account is empty" are two different
# claims. Terraform reports on what IT tracked; anything created outside that
# state — by hand, or by a run whose state was lost — is invisible to it.
# Ask AWS instead.
# ---------------------------------------------------------------------------
log "Verifying against AWS, not against terraform"

INSTANCES=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=$TAG" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' \
  --output text 2>/dev/null || true)

VOLUMES=$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=tag:Project,Values=$TAG" \
  --query 'Volumes[].[VolumeId,Size,State]' --output text 2>/dev/null || true)

EIPS=$(aws ec2 describe-addresses --region "$REGION" \
  --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' \
  --output text 2>/dev/null || true)

echo
printf '  %-22s %s\n' "instances:" "${INSTANCES:-none}"
printf '  %-22s %s\n' "tagged volumes:" "${VOLUMES:-none}"
printf '  %-22s %s\n' "unattached EIPs:" "${EIPS:-none}"
echo

if [[ -z "$INSTANCES" && -z "$VOLUMES" && -z "$EIPS" ]]; then
  ok "==> Clean. Nothing is billing."
  echo
  echo "Rebuild with ./scripts/lab-up.sh — about an hour to a healthy cluster,"
  echo "entirely from git. Your screenshots and DEMO-RESULTS are unaffected."
else
  err "==> SOMETHING IS STILL THERE. Read the list above."
  echo
  echo "An unattached Elastic IP bills while it is NOT attached, which is exactly"
  echo "when you have forgotten it exists. Release it:"
  echo "    aws ec2 release-address --region $REGION --allocation-id <id>"
  exit 1
fi
