# platform-gitops

The declared state of the cluster. **ArgoCD watches this repository and nothing
else deploys.** After the bootstrap below there is exactly one `kubectl apply`
in the entire project, and it is the root Application.

Application source lives in the companion repo, `k8s-platform-app`.

---

## Before the first sync — replace these

Nothing works until `REPLACE_ME` is gone. Find every occurrence:

```bash
grep -rn "REPLACE_ME" .
```

| Placeholder | Becomes | Appears in |
|---|---|---|
| `https://github.com/REPLACE_ME/platform-gitops.git` | Your GitOps repo URL, real capitalisation | `argocd/**` |
| `ghcr.io/REPLACE_ME/api` · `ghcr.io/REPLACE_ME/web` | Your GHCR namespace, **lowercase** | `overlays/**/values-*.yaml` |

**These are two different strings, and a single blanket replace gets one of them
wrong.** GHCR lowercases the owner when it publishes, so `Syed-Amjad` becomes
`syed-amjad` in the registry path while the GitHub URL keeps its capitals.
Replace by context:

```bash
# GitHub URLs keep their capitals
grep -rl REPLACE_ME . | xargs sed -i 's|github\.com/REPLACE_ME|github.com/Syed-Amjad|g'

# GHCR image paths must be lowercase
grep -rl REPLACE_ME . | xargs sed -i 's|ghcr\.io/REPLACE_ME|ghcr.io/syed-amjad|g'
```

Get the casing wrong and the failure arrives at **wave 3** as an
`ImagePullBackOff` that reads like a broken manifest. It is not — the kubelet is
asking a registry for a path that was never published.

If your images are private, ArgoCD does not pull them — the kubelet does. Create
a pull secret in each app namespace and reference it, or make the packages
public while you are demonstrating.

---

## Bootstrap, in order

```bash
./scripts/bootstrap-cluster.sh       # k3s, helm, istioctl, Istio, Kiali
./scripts/install-platform-deps.sh   # Vault (dev mode) + External Secrets
./scripts/vault-seed.sh              # seed secrets, wire Kubernetes auth
./scripts/install-argocd.sh          # ArgoCD + the --enable-helm flag

# the only manual apply in the project
kubectl apply -f argocd/projects/platform.yaml
kubectl apply -f argocd/root-app.yaml

watch -n2 'kubectl -n argocd get applications'
```

Then open the UIs:

```bash
./scripts/port-forwards.sh
```

**Use a `t3.xlarge` (16 GB).** The full stack — k3s, Istio, ArgoCD, Prometheus,
Grafana, Loki, Vault, External Secrets and the apps with their sidecars — sits
at roughly **7.4 GB**. An 8 GB node technically fits it and then evicts things
the moment Prometheus grows toward its limit; the failure looks like random pod
restarts rather than a sizing problem. The extra ~$0.08/hour is worth more than
the evening it costs you.

Sizing at 16 GB now also means the follow-on Zero-Trust project (Kyverno, Falco,
Trivy) drops onto the same machine with **no resize and nothing rebuilt**.

---

## Sync waves

Ordering is explicit, and it is the difference between a platform that comes up
on a fresh cluster and one that crash-loops.

| Wave | Application | Why here |
|---|---|---|
| 0 | `secrets` | Namespaces, ClusterSecretStore, ExternalSecrets. Everything downstream needs the Secrets to exist. |
| 1 | `observability` | kube-prometheus-stack. Brings the `ServiceMonitor` and `PrometheusRule` **CRDs**. |
| 2 | `logging`, `promtail`, `observability-config` | Loki registers against a Grafana that already exists; rules need the CRD from wave 1. |
| 3 | `webapp` | The application. Needs the Secret, the CRDs and the log collector. |
| 4 | `istio-traffic` | DestinationRule subsets need pods to select, or they match nothing silently. |

ArgoCD completes and health-checks each wave before starting the next. Without
waves everything applies at once, the app starts before its Secret exists, and
you debug a crash-loop that looks like an application bug.

---

## Layout

```
argocd/
  projects/platform.yaml      AppProject — which repo may deploy what, where
  root-app.yaml               app-of-apps entry point
  applications/00..04         one Application per wave
charts/microservice/          one deployable VERSION (no Service — see Chart.yaml)
base/                         version-agnostic Services only
overlays/{dev,prod}/          own Namespace + Kustomize renders the chart per version
istio/                        Gateway, DestinationRule, VirtualService, STRICT mTLS
observability/                Helm values, PrometheusRules, dashboards-as-code
secrets/                      ClusterSecretStore + ExternalSecrets — references only
zabbix/                       host tier, with an honest note on when it is warranted
scripts/                      bootstrap and the six demonstrations
docs/
  DEMO-RESULTS.md             ← the measurements. Start here.
  RUNBOOK-canary.md           promotion and rollback, for someone else to follow
```

### Why the chart does not template a Service

The Service spans every version — that is what lets Istio split traffic between
`v1` and `v2` behind one stable DNS name. If each version's Helm release owned a
Service, two releases would fight over the same object. Services live in `base/`
as plain manifests instead.

### Why Helm *and* Kustomize

Not two tools doing one job. **Helm packages and templates; Kustomize expresses
environment differences.** `overlays/prod/kustomization.yaml` renders the chart
three times — `api-v1`, `api-v2`, `web` — then patches replica counts and
topology spread on top. `dev` renders it twice with smaller limits and no canary.

This requires `--enable-helm`. `scripts/install-argocd.sh` sets it. **Without
it, `kustomize build` emits nothing for `helmCharts:` and reports no error** —
so ArgoCD syncs "successfully" having deployed only the Services from `base/`.
That is the single most confusing failure in this repo, which is why it is
mentioned three times.

---

## Deploy versus release

Two different actions, deliberately separated:

- **Deploy** — CI pushes an image and writes the tag into
  `overlays/prod/values-api-v2.yaml`. ArgoCD rolls out v2 pods. **No user
  traffic reaches them.**
- **Release** — a human edits the weights in `istio/api-traffic.yaml`.

So broken code can sit in the cluster harming nobody, and shipping is not the
same decision as releasing. Full procedure in
[`docs/RUNBOOK-canary.md`](docs/RUNBOOK-canary.md).

---

## Lab-only, and stated as such

- **Vault runs in dev mode** — unsealed, in-memory, root token, and it loses
  everything when the pod restarts. Correct for demonstrating the External
  Secrets pattern; not a production Vault deployment.
- **Rotation updates the Secret, not the running process.** `envFrom` is read at
  container start, so pods keep the old value until restarted. Automating that
  needs a file mount with a watcher, or Reloader.
- **Alertmanager posts to a webhook**, not a real destination, unless you
  configure SMTP.
- **Zabbix is included for CV completeness** with an honest note that a
  greenfield Kubernetes estate would not add it — see `zabbix/README.md`.

Leave these in the write-up. On the previous project, statements exactly like
these did more for its credibility than any of the green output did.
