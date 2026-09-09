# Experiment 01 — Enroll a namespace & verify ztunnel sees it

**Goal:** add a namespace to ambient with a single label and confirm ztunnel is
now proxying its workloads — with zero pod restarts and no sidecars.

**Prereqs:** cluster + ambient + sample apps installed
(`make all`, or scripts 01–03).

---

## 1. Look at the "before" state

The sample apps are running but not in the mesh yet:

```bash
kubectl get ns ambient-demo -L istio.io/dataplane-mode
# DATAPLANE-MODE column is empty

istioctl ztunnel-config workloads --workload-namespace ambient-demo
# httpbin/curl show up as workloads, but are NOT ambient-captured yet
```

Notice the pods have exactly **one** container each (no sidecar):

```bash
kubectl -n ambient-demo get pods -o 'custom-columns=POD:.metadata.name,CONTAINERS:.spec.containers[*].name'
```

## 2. Enroll the namespace

```bash
kubectl label namespace ambient-demo istio.io/dataplane-mode=ambient
```

That's the whole thing. Confirm:

```bash
kubectl get ns ambient-demo -L istio.io/dataplane-mode
# DATAPLANE-MODE = ambient
```

The pods are **not** restarted — check their age and restart count:

```bash
kubectl -n ambient-demo get pods
# AGE unchanged, RESTARTS still 0, still 1/1 container
```

## 3. Verify ztunnel now captures the workloads

```bash
istioctl ztunnel-config workloads --workload-namespace ambient-demo
```

**Expected:** both `httpbin` and `curl` appear with a protocol/HBONE column
indicating they are now ambient-captured (e.g. `PROTOCOL=HBONE`). Compare with
the "before" output from step 1.

Also confirm ztunnel learned their identities:

```bash
istioctl ztunnel-config workloads --workload-namespace ambient-demo -o json | \
  jq -r '.[] | "\(.name)\t\(.node)\t\(.protocol)"'
```

## 4. Generate traffic and watch ztunnel

In one terminal, follow the ztunnel logs:

```bash
kubectl -n istio-system logs ds/ztunnel -f
```

In another, send requests:

```bash
kubectl -n ambient-demo exec deploy/curl -- \
  sh -c 'for i in 1 2 3; do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done'
```

**Expected:** ztunnel log lines appear for the connections (source/destination
identities, bytes, direction). Before enrollment, these requests produced *no*
ztunnel logs.

---

## What just happened

- The `istio.io/dataplane-mode=ambient` label told **istio-cni** to start
  capturing traffic for pods in `ambient-demo` and hand it to the node's
  **ztunnel** — without touching the pods.
- istiod pushed the workloads to ztunnel over xDS, so `ztunnel-config workloads`
  now shows them as HBONE-capable.
- Traffic between `curl` and `httpbin` now flows *through* ztunnel (and is
  mTLS-encrypted — you'll prove that in Experiment 02).

## Cleanup / reset

To un-enroll (leave the apps running, remove them from the mesh):

```bash
kubectl label namespace ambient-demo istio.io/dataplane-mode-
```
