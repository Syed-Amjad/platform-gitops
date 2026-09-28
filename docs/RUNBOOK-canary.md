# Runbook — Canary Release and Rollback

Written to be followed by someone who did not build this. If you cannot hand it
to a colleague and have them promote a release without asking you a question,
it is not finished.

**The rule that governs everything below: no `kubectl` in a release.** If you
find yourself typing `kubectl edit` or `kubectl apply` to change traffic, stop —
ArgoCD will revert it within about 30 seconds anyway, and you will have proved
that self-heal works rather than that you shipped anything.

---

## What "deploy" and "release" mean here

They are two different actions, and separating them is the whole point of
progressive delivery.

| | Trigger | Effect |
|---|---|---|
| **Deploy** | Push to `main` in `k8s-platform-app` | CI builds an image and writes the new tag into `overlays/prod/values-api-v2.yaml`. ArgoCD rolls out v2 pods. **No user traffic reaches them.** |
| **Release** | A human edits weights in `istio/api-traffic.yaml` | Traffic starts flowing to v2. |

So a deploy is automatic and safe; a release is deliberate. Broken code can sit
in the cluster all day harming nobody.

---

## Promoting a canary

### Step 0 — Confirm what you are promoting

```bash
kubectl -n webapp-prod get deploy -l app=api -o wide
kubectl -n webapp-prod get virtualservice api -o yaml | grep -A6 'weighted-split'
```

Check the v2 image tag matches the commit you intend to ship. Promoting a stale
canary because CI failed quietly is a real and unglamorous way to cause an
incident.

### Step 1 — Test v2 specifically, before anyone else sees it

```bash
CANARY_HEADER=1 ./scripts/demo-canary.sh 50
```

Every response should report `v2`. This is header-based routing — the
`x-canary: true` rule sits **first** in the VirtualService, so it wins before
the weighted split is evaluated. It lets you exercise a new version against
production dependencies with zero public exposure.

If some responses say `v1`, the header rule is not first. Check rule order.

### Step 2 — 90 / 10

Already the committed default. Measure it:

```bash
./scripts/demo-canary.sh 200
```

Then **watch, do not just look.** Give it at least 10 minutes and check:

```promql
webapp:request_error_ratio5m:by_version{version="v2"}
```

Compare against `version="v1"`. The `CanaryErrorRateHigh` alert fires at 5%,
but a canary that is merely *worse* than stable — 2% against 0.1% — is still a
failed release and will not page you. Look at the number.

### Step 3 — 50 / 50

Edit `istio/api-traffic.yaml`:

```yaml
- destination: { host: api.webapp-prod.svc.cluster.local, subset: v1 }
  weight: 50
- destination: { host: api.webapp-prod.svc.cluster.local, subset: v2 }
  weight: 50
```

```bash
git commit -am "release: api v2 to 50%" && git push
```

Watch ArgoCD sync it, then re-measure and record the result.

**Scale v2 up before you shift the weight**, or you are sending half the traffic
to one pod. In `overlays/prod/values-api-v2.yaml`, raise `replicaCount` to match
v1. Both changes can go in the same commit.

### Step 4 — 100 %

```yaml
  weight: 0    # v1
  weight: 100  # v2
```

Leave v1 deployed at zero weight for at least a few hours. Rollback is then a
one-line revert with pods that are already running and warm — not a
`kubectl rollout undo` against pods that no longer exist.

### Step 5 — Retire v1

Once you are confident:

1. Copy the v2 image tag into `values-api-v1.yaml`
2. Reset weights to `v1: 100, v2: 0`
3. Commit

v1 is now the new version, and the next canary starts from a clean 90/10. This
keeps "v1" meaning *stable* and "v2" meaning *candidate*, permanently, rather
than accumulating v3, v4, v5 subsets nobody can reason about.

---

## Rolling back

### The fast path — under a minute

Revert the weights and push:

```bash
git revert --no-edit HEAD
git push
```

ArgoCD applies it on its next poll (default 3 minutes). To not wait:

```bash
argocd app sync istio-traffic
```

**That is the whole rollback.** No image rebuild, no redeploy — v1 pods have
been running the entire time. This is why the weighted split is worth the
complexity over a straight rolling update.

### If ArgoCD itself is the problem

The only situation where touching the cluster directly is correct. **Disable
self-heal first**, or your change is reverted while you are still typing:

```bash
argocd app set istio-traffic --sync-policy none
kubectl -n webapp-prod edit virtualservice api      # weights to v1: 100
```

Then fix git, re-enable, and re-sync:

```bash
argocd app set istio-traffic --sync-policy automated --self-heal --auto-prune
```

**Record in `docs/DEMO-RESULTS.md` that you did this, and why.** An emergency
manual change that never makes it back into git is how a cluster starts drifting
from its declared state — and the drift is invisible precisely because ArgoCD
now reports Synced against the wrong thing.

---

## When it goes wrong

### The canary gets no traffic at all

In order of likelihood:

1. **Pod labels.** The DestinationRule subsets on `version`. Check it exists:
   ```bash
   kubectl -n webapp-prod get pods --show-labels | grep api
   ```
2. **Sidecar not injected.** No proxy means no routing — the VirtualService is
   accepted and does nothing:
   ```bash
   kubectl -n webapp-prod get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
   ```
   Two containers per pod is correct. One means the namespace was missing
   `istio-injection=enabled` when the pod started — restart it.
3. **Port name.** The Service port must be named `http`. Named `web`, or
   unnamed, Istio treats the traffic as opaque TCP and L7 rules cannot apply.

### Both versions answer when you sent the canary header

Rule order. The `x-canary` match must be the **first** entry under `http:`.

### ArgoCD shows OutOfSync forever

Almost always the Istio sidecar: ArgoCD did not write those containers and
therefore sees drift it cannot fix. `argocd/applications/03-app.yaml` already
carries `ignoreDifferences` for `istio-proxy` and `istio-init` — confirm the
Application actually has it:

```bash
kubectl -n argocd get app webapp -o yaml | grep -A8 ignoreDifferences
```

### Everything is Healthy but nothing was deployed

The `--enable-helm` flag. `kustomize build` produces **no output and no error**
for `helmCharts:` entries without it, so ArgoCD honestly reports success having
applied only the Services from `base/`.

```bash
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.kustomize\.buildOptions}'
```

Expect `--enable-helm`. If it is empty, re-run `scripts/install-argocd.sh` and
restart `argocd-repo-server`.
