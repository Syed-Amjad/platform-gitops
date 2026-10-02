#!/usr/bin/env bash
# Bring the lab back up: provision the box and print how to reach it.
#
# Run from your workstation (WSL), not from the box. This creates the machine
# that the other scripts in this directory then run ON.
#
#   ./scripts/lab-up.sh
#
# This deliberately stops at a provisioned, reachable box. The cluster itself is
# built by bootstrap-cluster.sh and friends, over SSH, and wiring those together
# into one command would hide the step where things actually go wrong.
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m%s\033[0m\n' "$*"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$HERE/terraform"
export AWS_PAGER=""

cd "$TF_DIR"

log "terraform init"
terraform init -input=false

# ---------------------------------------------------------------------------
# The security group opens :22 to ONE address, auto-detected at plan time.
# A home connection's public IP changes without warning, so a box that was
# reachable yesterday may refuse you today — and the symptom is an SSH timeout
# that looks like a dead instance rather than a firewall rule.
#
# Re-running apply is the fix: the http data source re-detects and the rule is
# updated in place.
# ---------------------------------------------------------------------------
MYIP="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')"
log "Your current public address is ${MYIP} — SSH will be opened to this /32"

log "terraform apply"
terraform apply -auto-approve

IP="$(terraform output -raw public_ip)"

log "Waiting for SSH to answer on ${IP}"
for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=accept-new \
         -o ConnectTimeout=5 -o BatchMode=yes \
         "ubuntu@${IP}" true 2>/dev/null; then
    ok "    SSH is up after $((i*5))s"
    break
  fi
  printf '    still waiting (%ss)\n' "$((i*5))"
  sleep 5
done

cat <<EOF

$(terraform output -raw hourly_cost_reminder)

==> Box is up at ${IP}

Open a SECOND terminal and keep it running — every UI is reached through this
tunnel, because no UI port is open in the security group:

  $(terraform output -raw tunnel_command)

Then, in that SSH session, build the cluster:

  sudo apt-get update && sudo apt-get install -y git
  git clone https://github.com/Syed-Amjad/platform-gitops.git
  cd platform-gitops
  ./scripts/bootstrap-cluster.sh
  ./scripts/install-platform-deps.sh
  ./scripts/vault-seed.sh
  ./scripts/install-argocd.sh
  kubectl apply -f argocd/projects/platform.yaml
  kubectl apply -f argocd/root-app.yaml
  watch -n2 'kubectl -n argocd get applications'

When you stop for the day:

  ./scripts/lab-down.sh

EOF
