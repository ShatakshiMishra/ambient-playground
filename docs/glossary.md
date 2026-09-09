# Glossary

**Ambient mesh** — Istio's sidecar-less data plane, split into an L4 secure
overlay (ztunnel) and an on-demand L7 layer (waypoints).

**ztunnel (zero-trust tunnel)** — Rust per-node DaemonSet proxy. Handles mTLS,
L4 authorization and TCP telemetry for enrolled workloads. Not an L7 proxy.

**Waypoint** — an Envoy proxy deployed on demand (via the Kubernetes Gateway
API), per namespace or per service account, that applies L7 policy.

**HBONE** — HTTP-Based Overlay Network Encapsulation. Tunnels TCP inside an
HTTP/2 `CONNECT` stream secured with mTLS, on port 15008.

**SPIFFE / SPIFFE ID** — a standard workload-identity URI, e.g.
`spiffe://cluster.local/ns/foo/sa/bar`. Encoded into the X.509 certs used for
mTLS.

**mTLS (mutual TLS)** — both client and server present certificates; each
verifies the other's identity. In ambient, ztunnel does this transparently.

**istiod** — the Istio control plane: certificate authority + xDS config server.

**istio-cni** — node component that programs traffic redirection so an enrolled
pod's traffic is captured into the node's ztunnel, without changing the pod.

**xDS** — the discovery API family Envoy/ztunnel use to receive config from
istiod. ztunnel uses a slim, workload-centric subset.

**Enrollment** — adding a namespace (or pod) to ambient via the label
`istio.io/dataplane-mode=ambient`.

**Workload** — a mesh endpoint (pod or VM) as ztunnel sees it: IPs, node,
identity, HBONE capability.

**AuthorizationPolicy** — Istio CRD expressing allow/deny rules. In ambient,
L4-only policies are enforced by ztunnel; L7 rules require a waypoint.

**Trust domain** — the administrative boundary in a SPIFFE ID (default
`cluster.local`).

**kind** — Kubernetes IN Docker; runs a throwaway cluster locally for these labs.
