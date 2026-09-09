# 01 — Ambient mesh architecture & where ztunnel fits

## The problem ambient solves

The classic Istio data plane injects an **Envoy sidecar** into every pod. That
gives you full L7 features but costs a container per pod, adds latency, couples
proxy upgrades to pod restarts, and forces L7 processing even on workloads that
only need mTLS.

**Ambient mesh** removes the sidecar and splits the data plane into two
independently adoptable layers:

1. **Secure L4 overlay** — provided by **ztunnel**, a per-node DaemonSet.
2. **L7 processing** — provided by **waypoint** proxies, added only where needed.

You can adopt just the L4 layer (mTLS + L4 authz + telemetry) and never run a
single Envoy in the request path.

## ztunnel: the node proxy

- **Deployment shape:** a DaemonSet in `istio-system`, one pod per node
  (`app=ztunnel`). It proxies traffic for *all* enrolled pods on its node.
- **Language:** Rust — chosen for a small, predictable memory/CPU footprint
  since it's a shared, always-on component.
- **Responsibilities:**
  - Terminate/originate **mTLS** for enrolled workloads.
  - Enforce **L4 `AuthorizationPolicy`** (allow/deny by SPIFFE identity, port,
    namespace).
  - Emit **TCP-level telemetry** (bytes, connections) as Prometheus metrics.
  - Move traffic between nodes using the **HBONE** tunnel.
- **What it is *not*:** it is not an HTTP proxy. It does not parse your
  application's L7 (HTTP headers, paths, gRPC methods). Anything L7 requires a
  **waypoint**.

### Identity

Each workload gets a **SPIFFE** identity of the form:

```
spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>
```

istiod (the control plane) issues short-lived X.509 certificates for these
identities. ztunnel presents the *source* workload's identity when it originates
a connection and validates the *destination* identity on the other side — that's
what makes the mTLS mutual and what L4 authorization policies match on.

### How ztunnel learns the world: xDS

ztunnel is configured by **istiod** over a slimmed-down **xDS** API. Instead of
Envoy's full CDS/LDS/RDS/EDS, ztunnel consumes a workload-centric API describing:

- **Workloads** — every pod/VM in the mesh: its IPs, node, identity, and whether
  it's ambient/HBONE-capable.
- **Services** — VIPs and their backing workloads.
- **Authorization policies** — the L4 rules to enforce.

You can see exactly this state with `istioctl ztunnel-config` (Experiment 5).

## Waypoints: the L7 layer

A **waypoint** is an Envoy proxy deployed *on demand* — per namespace or per
service account — using the Kubernetes **Gateway API**. When a destination has a
waypoint, ztunnel sends traffic *through* the waypoint (again over HBONE), which
applies L7 policy (HTTP routing, header manipulation, L7 authz, retries, fault
injection) before the traffic reaches the destination's ztunnel and pod.

Key point: **waypoints are opt-in and decoupled**. Adding L7 features to one
service doesn't force a proxy onto everything else.

```
L4 only:     client ─▶ ztunnelA ══HBONE══▶ ztunnelB ─▶ server
L4 + L7:     client ─▶ ztunnelA ══HBONE══▶ waypoint ══HBONE══▶ ztunnelB ─▶ server
```

## The control plane

- **istiod** — issues certificates (acts as the CA), computes and pushes xDS to
  ztunnel and waypoints, and watches Kubernetes for Services, workloads and
  policies.
- **istio-cni** — a node component that programs traffic **redirection** so an
  enrolled pod's traffic is captured into the node's ztunnel *without* modifying
  the pod. (Details in [02-traffic-redirection-and-hbone.md](02-traffic-redirection-and-hbone.md).)

## Component summary

| Component | Kind | Namespace | Role |
|-----------|------|-----------|------|
| istiod | Deployment | istio-system | control plane / CA / xDS |
| ztunnel | DaemonSet | istio-system | per-node L4 proxy (mTLS, authz, telemetry) |
| istio-cni | DaemonSet | istio-system | sets up per-pod traffic redirection |
| waypoint | Deployment (Gateway) | your namespace | on-demand L7 proxy |

## Further reading

- Istio ambient docs: <https://istio.io/latest/docs/ambient/>
- ztunnel source: <https://github.com/istio/ztunnel>
- HBONE / ambient design notes in the istio/ztunnel repo `architecture.md`.
