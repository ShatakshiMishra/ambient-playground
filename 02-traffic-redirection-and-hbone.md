# 02 — Traffic redirection & the HBONE tunnel

This is the "how does my packet actually get into ztunnel and across the
network?" chapter.

## Step 1 — Enrollment

A namespace joins ambient with a single label:

```bash
kubectl label namespace <ns> istio.io/dataplane-mode=ambient
```

No pod restart, no sidecar injection. From that moment, **istio-cni** starts
capturing the traffic of pods in that namespace.

## Step 2 — Redirection into the node ztunnel

When a pod is enrolled, **istio-cni** programs redirection *inside the pod's own
network namespace* so that:

- traffic **leaving** the pod is sent to the node-local ztunnel's **outbound**
  listener, and
- traffic **arriving** for the pod is delivered via ztunnel's **inbound** path.

Modern Istio (≈1.22+) does this with an **in-pod** redirection model: istio-cni
enters the pod netns and sets up the capture there, and ztunnel reaches the pod
through a socket the CNI hands it. (Earlier ambient builds used a node-level
approach with GENEVE tunnels and iptables mark-based routing. The user-visible
behavior is the same; only the plumbing changed — don't be surprised if older
blog posts describe it differently.)

The important mental model:

> An enrolled pod's TCP traffic is transparently intercepted and handed to the
> ztunnel running on the **same node**, in both directions. The application is
> unaware.

## Step 3 — ztunnel picks a path

For an outbound connection, the source ztunnel looks up the destination in its
xDS-provided workload/service tables and decides:

- **Destination is ambient (HBONE-capable):** open an HBONE tunnel to the
  destination node's ztunnel (or to the destination's waypoint, if one exists).
- **Destination is not in the mesh:** send plain traffic (subject to policy).

## Step 4 — HBONE

**HBONE = HTTP-Based Overlay Network Encapsulation.** The original TCP stream is
carried as the body of an **HTTP/2 `CONNECT`** request:

```
CONNECT <target-ip>:<target-port> HTTP/2
```

- The HTTP/2 connection runs over **mTLS** (TLS 1.3) using the source and
  destination **SPIFFE** identities.
- It targets ztunnel's HBONE port **`15008`** on the destination node.
- Multiple application connections can be **multiplexed** as separate HTTP/2
  streams over one tunnel.

Why HTTP/2 CONNECT instead of a raw TLS tunnel? It gives multiplexing, standard
metadata (the target address travels in the `:authority`/CONNECT line), and easy
interop with the L7 waypoint layer, which is Envoy speaking the same protocol.

```
 source pod
    │  (plain TCP, captured by CNI)
    ▼
 ztunnel (node A) ──┐
                    │  HTTP/2 CONNECT  ]
                    │  over mTLS       ]  ==  HBONE, port 15008
                    ▼                  ]
 ztunnel (node B) ──┘
    │  (plain TCP into the pod)
    ▼
 destination pod
```

## ztunnel's listener ports (reference)

Ports are an implementation detail and can change between releases, but as a
map of what you'll see:

| Port | Purpose |
|------|---------|
| **15008** | **HBONE** — inbound mTLS/HTTP-2 CONNECT tunnel (the important one) |
| 15001 | outbound capture |
| 15006 | inbound plaintext capture |
| 15020 | Prometheus metrics / health |
| 15021 | health check |

## What travels where — quick reference

| Scenario | Path |
|----------|------|
| ambient → ambient, no waypoint | podA → ztunnelA →(HBONE)→ ztunnelB → podB |
| ambient → ambient, dest has waypoint | podA → ztunnelA →(HBONE)→ waypoint →(HBONE)→ ztunnelB → podB |
| ambient → non-mesh | podA → ztunnelA → destination (plain, policy applied) |
| non-mesh → ambient service | (depends on destination exposure; may bypass mTLS) |

## Verifying it yourself

- **Confirm the tunnel port:** in Experiment 2 you'll see connections to
  `:15008` and mTLS in ztunnel logs.
- **Confirm identities:** `istioctl ztunnel-config certificates` shows the
  SPIFFE certs ztunnel holds.
- **Confirm redirection:** in Experiment 5 you inspect the ztunnel pod and the
  istio-cni DaemonSet.
