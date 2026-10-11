# Screenshots

Captured from a real build on 2026-10-10 — k3s on a `t3.xlarge`, Istio 1.31.1,
ArgoCD v3.5.3, kube-prometheus-stack 65.1.1, Loki, Vault (dev mode), External
Secrets 2.11.0. The cluster was destroyed the same day; everything here is
reproducible from this repository.

**Redaction:** three images have a red-outlined blurred box. Those cover a
bootstrap password and a commit-author email address. Nothing technical is
hidden.

---

## Bootstrap

| | |
|---|---|
| `01-bootstrap-k3s-istio.png` | k3s v1.36.4, Helm 3.22.0 and istioctl 1.31.1 installing on a fresh node |
| `02-cluster-ready-memory.png` | Istio + Kiali up. `free -h` reads **1.4 GiB of 15 GiB** before ArgoCD and Prometheus arrive |
| `03-kustomize-enable-helm-trap.png` | **The trap this repo warns about three times.** Without `--enable-helm`, exit code 1; with it, 9 resources render |

## GitOps delivery

| | |
|---|---|
| `04-argocd-install.png` | Server-side apply — needed because the ApplicationSet CRD exceeds the 262144-byte annotation limit. The `--enable-helm` patch lands at the end |
| `05-root-app-sync-timing.png` | The only two manual `kubectl apply` commands in the project |
| `06-argocd-root-tree.png` | App-of-apps: `root` Healthy, children fanning out |
| `07-argocd-all-apps-synced.png` | All 8 Applications Synced and Healthy |
| `08-argocd-webapp-tree.png` | `webapp` down to Deployment → ReplicaSet → Pods |

## Secrets

| | |
|---|---|
| `09-vault-seed.png` | Kubernetes auth enabled, policy scoped to two paths, secrets seeded |
| `10-eso-v1-api-resources.png` | ESO serving **`v1`**, not `v1beta1` — the evidence behind defect 3 |
| `11-externalsecret-synced.png` | `SecretSynced True`. The Secret exists in the cluster and appears nowhere in git |

## Observability

| | |
|---|---|
| `12-prometheus-targets.png` | Scrape targets UP |
| `13-grafana-metrics-logs-correlated.png` | **The one to lead with.** `rate(http_requests_total)` split by version, beside Loki logs for the same namespace and window |
| `14-grafana-loki-500-errors.png` | `{namespace="webapp-prod"} \|= "500"` — the error spike visible in the log volume |
| `15-kiali-overview-during-errors.png` | 24.59% error rate on `api`, 0.00% on `web`. Deliberate: `/boom` driving the SLO rule |

## Service mesh and canary

| | |
|---|---|
| `16-kiali-traffic-graph.png` | `istio-ingressgateway → web → api → {v1, v2}`. 3 apps, 4 versions, 5 edges, 100% success |
| `17-kiali-graph-during-errors.png` | The same graph during the alert demo — red edges, 24.76% error |
| `18-kiali-istio-config-valid.png` | All five Istio objects valid, **after** fixing the port ambiguity of defect 16 |
| `19-demo-selfheal.png` | Scaled to 9 by hand, **reverted to 3 after 4 seconds** |
| `20-canary-90-10.png` | Configured 90/10, **measured 171 / 29 (85.5% / 14.5%)** |
| `21-canary-50-50.png` | Configured 50/50, **measured 102 / 98 (51.0% / 49.0%)** |
| `22-canary-header-defect.png` | `x-canary: true` expected 0/50, **got 46/4** — defect 17, the header never survives the `web → api` hop |

## Defects

| | |
|---|---|
| `23-defect-apps-outofsync.png` | Four Applications stuck. One AppProject allowlist entry short; only one of the four errors named the real cause |

---

Full reasoning for every defect is in [`../DEMO-RESULTS.md`](../DEMO-RESULTS.md).
