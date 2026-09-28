# Demonstration Results

**This file is the point of the project.** The manifests describe intent;
these are the observations. On the HA platform the equivalent file
(`DR-test-results.md`) turned out to be the single most persuasive artifact in
the repository, and this one works the same way.

Fill in a row every time you run a demonstration. **Do not tidy out the
failures** — a table containing only successes tells a reader you deleted the
interesting rows.

Environment: k3s on `t3.xlarge`, Istio `demo` profile, ArgoCD, kube-prometheus-stack,
Loki, Vault (dev mode), External Secrets Operator.

---

## The six demonstrations

| # | Demonstration | Command | Expected | Result | Date |
|---|---|---|---|---|---|
| 1 | **Self-heal** | `./scripts/demo-selfheal.sh` | Manual scale to 9 reverted to the git-declared count | | |
| 2 | **Prune** | Delete a manifest from git, commit | Resource removed from the cluster | | |
| 3 | **Sync waves** | Fresh sync of `root` | secrets → observability → logging → app → istio, in order | | |
| 4 | **Alert fires** | `./scripts/demo-alerts.sh errors` | `WebappErrorBudgetBurn` pending → firing; routed by severity | | |
| 5 | **Metric → log correlation** | Take the pod name from the alert, query Loki | That pod's logs at that timestamp | | |
| 6 | **Secret rotation** | `./scripts/demo-secret-rotation.sh` | Kubernetes Secret updates with no deployment | | |

1, 4 and 6 are the persuasive ones. Capture terminal output, not descriptions.

---

## Canary measurements

Run `./scripts/demo-canary.sh 200` at each step. **Record the measured split,
not the configured one** — asserting that 90/10 was configured proves nothing;
counting 181 v1 responses against 19 v2 proves the mesh is actually routing.

| Weights in git | Requests | v1 measured | v2 measured | Deviation | Date |
|---|---|---|---|---|---|
| 90 / 10 | 200 | | | | |
| 50 / 50 | 200 | | | | |
| 0 / 100 | 200 | | | | |
| header `x-canary: true` | 50 | 0 expected | 50 expected | | |

Expect some deviation from the configured weights at low request counts —
Istio's distribution is probabilistic per request, not a strict round robin.
A 90/10 split measured over 200 requests landing at 87/13 is correct behaviour,
not a misconfiguration. Say so rather than quietly rounding the number.

---

## Timings worth recording

| Measurement | How | Result |
|---|---|---|
| Self-heal reversion time | `demo-selfheal.sh` prints it | |
| Full sync from empty cluster to all-Healthy | `time` the root app sync | |
| Wave 0 → wave 4 ordering held? | ArgoCD UI timeline | |
| Alert pending → firing delay | Prometheus Alerts page | |
| Secret rotation propagation | `demo-secret-rotation.sh` prints it | |

---

## Screenshots to capture

1. ArgoCD — app-of-apps tree, everything Synced/Healthy
2. Sync-wave ordering visible in the ArgoCD timeline
3. Self-heal: the manual scale reverted (before and after in one frame)
4. Prometheus **Targets** page — the `api` and `web` targets UP
5. A **firing** alert, with severity routing visible in Alertmanager
6. **Grafana with metrics and Loki logs on one screen** ← the money shot
7. A LogQL query returning the failing pod's logs
8. `kubectl get externalsecret` showing `SecretSynced`, beside a `grep` of the
   repo proving the value is not in git
9. Kiali showing the service graph and the live traffic split during a canary

Number 6 is the one to lead with: metrics and logs, correlated, in one view,
from a platform assembled entirely from git.

---

## What went wrong

Record every defect you find by running this rather than reading it. On the HA
platform six defects surfaced this way and they became the most interesting
section of the whole write-up.

<!--
Likely candidates, based on what usually bites in this stack:

- kustomize.buildOptions missing --enable-helm → the app Application syncs
  "successfully" and deploys nothing but the Services.
- serviceMonitorSelectorNilUsesHelmValues left at true → the target never
  appears and Prometheus reports no error.
- Istio port not named http* → VirtualService accepted, routing silently absent.
- ArgoCD fighting the Istio sidecar → permanent OutOfSync, selfHeal looping.
- PrometheusRule applied before its CRD exists → "no matches for kind".
- ESO API version mismatch (v1beta1 vs v1) → "no matches for kind ExternalSecret".
-->

### Found before the cluster existed — 2026-09-23

Four defects surfaced during a local dry run, before a single pod was scheduled.
Recording them here because *when* a defect is found is part of the result: each
of these would have presented on the box as something other than what it was.

| # | Defect | How it would have presented | Fix |
|---|---|---|---|
| 1 | **Default VPC had been stripped.** All six default subnets deleted, internet gateway deleted, and the main route table still carrying `0.0.0.0/0` to the dead IGW in state `blackhole`. | `terraform apply` succeeds, instance boots, SSH works — then `bootstrap-cluster.sh` hangs on `apt-get update`. Reads as a broken k3s install. | `terraform/network.tf` declares its own IGW, subnet, route table and association rather than inheriting account state. |
| 2 | **ESO chart repository moved.** `https://charts.external-secrets.io` now 302-redirects and `helm repo add` against it times out. | `install-platform-deps.sh` dies at step 2 with an error blaming the repository, not the move. | Repo URL changed to `https://external-secrets.io`. |
| 3 | **ESO 2.x serves only `v1`.** The three manifests in `secrets/` declared `external-secrets.io/v1beta1`, correct for 0.9.x–0.13.x. The script installed the chart *unpinned*, so it resolved to 2.11.0. | Wave 0 fails with `no matches for kind ClusterSecretStore` — which reads like a typo in a file that is actually correct for the version it was written against. | Manifests moved to `v1`; ESO pinned to `2.11.0` and Vault to `0.34.1`. Field names are identical between versions, so this was an `apiVersion` bump and nothing else. |
| 4 | **`values-api-v1.yaml` pins `tag: v1`, which CI never publishes.** CI builds SHA tags only — deliberately, never `:latest` — and rewrites only `values-api-v2.yaml` and `values-web.yaml`. Nothing ever creates `ghcr.io/syed-amjad/api:v1`. | Wave 3 comes up with `api-v2` and `web` Running and `api-v1` in `ImagePullBackOff`. One of three deployments failing looks like a flake, not a design gap. | On a fresh platform, v1 and v2 start from the same commit: after the first green CI run, copy that SHA into `values-api-v1.yaml` and commit. That commit *is* the deliberate human promotion the design calls for — see `RUNBOOK-canary.md` step 5. |

**One documented behaviour has also changed.** This repo warns three times that
`kustomize build` without `--enable-helm` "produces no output and reports no
error". On kustomize **v5.7.1** (bundled with kubectl v1.34.1) that is no longer
true — it exits 1 and names the generator:

```
$ kubectl kustomize overlays/prod
error: trouble configuring builtin HelmChartInflationGenerator with config: ...
exit code: 1        resources emitted: 0
```

With the flag, the same overlay renders 9 resources: 3 Deployments, 2 Services,
3 ServiceMonitors, 1 Namespace. The warning is still worth keeping — ArgoCD
bundles its own kustomize, and the silent-failure behaviour is what older
versions do — but the loud failure is the better outcome and it is worth saying
which version changed it.

---

## Honest notes to keep in the write-up

- **Vault runs in dev mode** — unsealed, in-memory, root token, and it loses
  everything on pod restart. Fine for demonstrating the External Secrets
  pattern; not a production Vault deployment. Say so.
- **Secret rotation updates the Secret, not the running process.** `envFrom` is
  read at container start, so the pods keep the old value until they restart.
  Making that automatic needs a file mount with a watcher, or Reloader. Claiming
  zero-restart rotation without that piece would be overclaiming.
- **Zabbix earns its place only where non-Kubernetes infrastructure exists.**
  In a greenfield Kubernetes estate you would not add it. That distinction is a
  more senior answer than deploying it and implying it was necessary.
- **Alertmanager notifications go to a webhook, not to a real destination**,
  unless you configure SMTP. An alert that fires into nothing is the same class
  of problem as everything else in this document.
