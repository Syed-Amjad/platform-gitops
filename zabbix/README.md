# Zabbix — the host tier

Your CV lists Zabbix alongside Prometheus. Framed carelessly that reads as
redundancy — two monitoring systems doing one job. Framed correctly it is a
genuine enterprise pattern, and the distinction is what makes it worth saying.

| Tier | Tool | Why that one |
|---|---|---|
| Kubernetes workloads, application metrics | **Prometheus** | Pull-based, label-rich, built for targets that appear and disappear constantly |
| Bare-metal hosts, network gear, appliances, Windows servers | **Zabbix** | Agent and SNMP based, built for long-lived infrastructure that Prometheus has no good way to reach |

## The honest position

**In a greenfield Kubernetes estate you would not add Zabbix.** It earns its
place where there is existing non-Kubernetes infrastructure to cover — switches,
storage arrays, hypervisors, Windows file servers — that Prometheus exporters
either cannot reach or would be a poor fit for.

Saying that in an interview is a stronger answer than deploying it and implying
it was necessary. It shows you chose a tool for a reason rather than because it
was on a list.

That is also exactly the situation at a company running a managed Linux fleet
alongside a Kubernetes platform, which is the environment this whole portfolio
is aimed at.

## Install

```bash
helm repo add zabbix https://cdn.zabbix.com/zabbix/integrations/kubernetes-helm/7.0
helm repo update
helm upgrade --install zabbix zabbix/zabbix-helm-chrt \
  -n monitoring --create-namespace \
  -f values.yaml
```

On a `t3.xlarge` this fits alongside everything else with room to spare. On an
8 GB node it does not — you would spend the afternoon debugging evictions rather
than learning anything.

Worth deploying at some point if you want to claim Zabbix honestly: right now
this directory documents the reasoning but nothing is running. A claim backed by
a values file is weaker than one backed by a screenshot.

## One pane of glass

The point of running both is *not* two dashboards. Export Zabbix metrics into
Prometheus so Grafana renders everything together:

```bash
helm upgrade --install zabbix-exporter prometheus-community/prometheus-zabbix-exporter \
  -n monitoring
```

Then add a Grafana panel querying `zabbix_*` series alongside the Kubernetes
ones. An operator should not have to know which system collected a number in
order to look at it.
