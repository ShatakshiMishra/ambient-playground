# ambient-playground

A hands-on lab repo for **experimenting with Istio's `ztunnel`** — the per-node
zero-trust tunnel proxy at the heart of **Istio ambient mesh**.

Every experiment runs on a local [kind](https://kind.sigs.k8s.io/) cluster, so
you can break things safely and start over in a minute. Each lab is a
self-contained folder with an objective, copy-pasteable steps, the **expected
output**, and an explanation of *what just happened inside ztunnel*.

> ⚠️ These are learning experiments, not production guidance. They target a
> recent Istio release where **ambient is GA (Istio ≥ 1.24)**. Exact ports,
> CLI flags and redirection internals evolve between releases — where a detail
> is version-sensitive it is called out.

---

## What is ztunnel? (30-second version)

Istio ambient mesh splits the data plane into two layers:

| Layer | Component | What it does |
|-------|-----------|--------------|
| **L4 secure overlay** | **`ztunnel`** (per-node DaemonSet, Rust) | mTLS, L4 authorization, TCP telemetry. Always on for enrolled pods. |
| **L7 processing** | **waypoint** proxy (Envoy, per-namespace/service, on demand) | HTTP routing, L7 authorization, retries, etc. Added only when you need it. |

`ztunnel` captures traffic for pods enrolled in ambient and carries it between
nodes inside **HBONE** — *HTTP-Based Overlay Network Encapsulation*: the TCP
stream is tunneled over an **HTTP/2 `CONNECT`** on port **15008**, wrapped in
**mTLS** using SPIFFE identities issued by istiod. No sidecar is injected into
your pods.

```
                    node A                                   node B
  ┌──────────────────────────────────┐      ┌──────────────────────────────────┐
  │  app pod ──▶ ztunnel (DaemonSet)  │      │  ztunnel (DaemonSet) ──▶ app pod  │
  │              │                    │      │            ▲                      │
  └──────────────┼────────────────────┘      └────────────┼─────────────────────┘
                 └────── HBONE: mTLS over HTTP/2 CONNECT (:15008) ──────┘
```

See [docs/01-architecture.md](docs/01-architecture.md) and
[docs/02-traffic-redirection-and-hbone.md](docs/02-traffic-redirection-and-hbone.md)
for the full picture.

---

## Prerequisites

You need these on your `PATH` (macOS/Linux):

- **Docker** (or Podman) — container runtime for kind
- **kind** ≥ 0.23
- **kubectl** ≥ 1.29
- **istioctl** ≥ 1.24 — install: `curl -L https://istio.io/downloadIstio | sh -` then add `istio-*/bin` to PATH
- **jq** (nice-to-have, for parsing config dumps)

Run the checker:

```bash
./scripts/00-prereqs.sh
```

---

## Quick start

```bash
make all        # prereqs → create cluster → install ambient → deploy sample apps
```

or step by step:

```bash
./scripts/00-prereqs.sh
./scripts/01-create-cluster.sh          # 3-node kind cluster (so HBONE crosses nodes)
./scripts/02-install-istio-ambient.sh   # istioctl install --set profile=ambient
./scripts/03-deploy-sample-apps.sh      # httpbin + curl client, NOT yet in the mesh
```

Then work through the experiments in order.

Tear everything down with:

```bash
make clean      # or: ./scripts/99-cleanup.sh
```

---

## The experiments

| # | Folder | You will learn |
|---|--------|----------------|
| 1 | [experiments/01-enroll-and-verify](experiments/01-enroll-and-verify/) | Enroll a namespace into ambient with one label; confirm ztunnel now knows your workloads (`istioctl ztunnel-config workloads`). |
| 2 | [experiments/02-mtls-and-hbone](experiments/02-mtls-and-hbone/) | Prove traffic is mTLS-encrypted over HBONE; read ztunnel access logs; inspect issued SPIFFE certs. |
| 3 | [experiments/03-l4-authorization](experiments/03-l4-authorization/) | Enforce an L4 `AuthorizationPolicy` at ztunnel (allow/deny by identity) with no sidecars and no waypoint. |
| 4 | [experiments/04-waypoint-l7](experiments/04-waypoint-l7/) | Add a waypoint proxy for L7 features; see how ztunnel hands HTTP off to the waypoint. |
| 5 | [experiments/05-ztunnel-internals](experiments/05-ztunnel-internals/) | Dig into the ztunnel pod: config dump, xDS state, Prometheus metrics, the CNI redirection path. |

Each folder's `README.md` is standalone.

---

## Repo layout

```
ambient-playground/
├── README.md
├── Makefile                     # convenience targets
├── docs/                        # conceptual background
│   ├── 01-architecture.md
│   ├── 02-traffic-redirection-and-hbone.md
│   └── glossary.md
├── scripts/                     # cluster + mesh lifecycle
│   ├── lib.sh
│   ├── 00-prereqs.sh
│   ├── 01-create-cluster.sh
│   ├── kind-config.yaml
│   ├── 02-install-istio-ambient.sh
│   ├── 03-deploy-sample-apps.sh
│   └── 99-cleanup.sh
├── manifests/
│   └── sample-apps.yaml         # httpbin + curl client
└── experiments/
    ├── 01-enroll-and-verify/
    ├── 02-mtls-and-hbone/
    ├── 03-l4-authorization/
    ├── 04-waypoint-l7/
    └── 05-ztunnel-internals/
```

## Handy command cheat-sheet

```bash
# ztunnel's view of the mesh
istioctl ztunnel-config workloads          # workloads ztunnel proxies
istioctl ztunnel-config services           # services it knows
istioctl ztunnel-config certificates       # mTLS certs per identity
istioctl ztunnel-config all -o json | jq   # everything

# live ztunnel behavior
kubectl -n istio-system logs ds/ztunnel -f            # access logs
kubectl -n istio-system get pods -l app=ztunnel -o wide
istioctl ztunnel-config log <ztunnel-pod> --level debug   # bump log level

# who is / isn't in the mesh
kubectl get ns -L istio.io/dataplane-mode
```

## License

MIT — see [LICENSE](LICENSE). Istio, ztunnel and related marks belong to their
respective owners; this repo is independent learning material.
