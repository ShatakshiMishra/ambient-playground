# Experiment 05 — Inside the ztunnel pod

**Goal:** stop treating ztunnel as a black box. Inspect its xDS-driven config,
its Prometheus metrics, its logs/log-levels, and the CNI redirection that feeds
it.

**Prereqs:** Experiments 01–02 done (some enrolled traffic to look at).

---

## 1. The DaemonSet and its pods

```bash
kubectl -n istio-system get ds ztunnel
kubectl -n istio-system get pods -l app=ztunnel -o wide   # one per node
```

Pick a pod to poke at:

```bash
ZT=$(kubectl -n istio-system get pod -l app=ztunnel -o jsonpath='{.items[0].metadata.name}')
echo "$ZT"
```

## 2. ztunnel's view of the mesh (xDS state)

These come straight from what istiod pushed:

```bash
istioctl ztunnel-config workloads     # every workload ztunnel proxies
istioctl ztunnel-config services      # services & their VIPs
istioctl ztunnel-config certificates  # mTLS identities/certs held
istioctl ztunnel-config all -o json | jq 'keys'   # top-level sections
```

Look at one workload in detail:

```bash
istioctl ztunnel-config workloads --workload-namespace ambient-demo -o json | \
  jq '.[] | {name, namespace, node, protocol, addresses: .workloadIps}'
```

## 3. Metrics (Prometheus)

ztunnel exposes metrics on port **15020**. Port-forward and scrape:

```bash
kubectl -n istio-system port-forward "$ZT" 15020:15020 >/dev/null 2>&1 &
sleep 2
curl -s localhost:15020/metrics | grep -E '^istio_tcp_(sent|received)_bytes_total|^istio_tcp_connections' | head
kill %1 2>/dev/null || true
```

**Expected:** TCP telemetry counters (bytes sent/received, connections opened/
closed), labeled with source/destination identity and namespace.

## 4. Logs & dynamic log level

```bash
kubectl -n istio-system logs "$ZT" --tail=20
istioctl ztunnel-config log "$ZT" --level debug   # crank up verbosity
# ... generate some traffic from the curl pod ...
istioctl ztunnel-config log "$ZT" --level info    # put it back
```

## 5. The redirection path (istio-cni)

ztunnel only works because **istio-cni** captures pod traffic into it:

```bash
kubectl -n istio-system get ds -l k8s-app=istio-cni-node -o wide 2>/dev/null || \
kubectl -n istio-system get pods | grep -i cni
```

Look at what the CNI node agent logged when it enrolled your pods:

```bash
CNI=$(kubectl -n istio-system get pod -l k8s-app=istio-cni-node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$CNI" ] && kubectl -n istio-system logs "$CNI" --tail=30 | grep -i -E 'ambient|redirect|ambient-demo' || \
  echo "CNI pod label may differ in your version; list with: kubectl -n istio-system get pods"
```

## 6. Resource footprint

A selling point of ambient is a lean shared proxy. Compare ztunnel's usage to a
would-be sidecar:

```bash
kubectl -n istio-system top pod -l app=ztunnel 2>/dev/null || \
  echo "metrics-server not installed; skip or install it to see CPU/memory"
```

---

## What just happened

- `istioctl ztunnel-config` reads ztunnel's **actual runtime state** (workloads,
  services, certs) — the slim, workload-centric xDS ztunnel gets from istiod.
- ztunnel emits **L4 telemetry** on :15020 with identity labels — usable by
  Prometheus/Grafana/Kiali.
- **istio-cni** is the piece that transparently routes enrolled-pod traffic into
  ztunnel; without it, nothing would be captured.

## Where to go next

- Wire up Prometheus + Kiali (`samples/addons` in the Istio release) to visualize
  the L4 telemetry.
- Read the ztunnel source & design docs: <https://github.com/istio/ztunnel>.
- Re-run Experiment 02 with `--level debug` to watch a full HBONE handshake.
