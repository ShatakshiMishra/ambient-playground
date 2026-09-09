# Experiment 04 — Add a waypoint for L7 policy

**Goal:** see the second ambient layer. ztunnel handles L4; when you need **L7**
(HTTP method/path routing, L7 authz, retries…) you deploy a **waypoint** proxy.
Here we allow only `GET` to `httpbin` — a rule ztunnel *cannot* enforce alone.

**Prereqs:** Experiment 01 done. The Gateway API CRDs must be present (recent
Istio installs them; if not, see step 0).

---

## 0. Ensure Gateway API CRDs (usually already installed)

```bash
kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && echo "Gateway API present" || \
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
```

## 1. Deploy a waypoint for the namespace

```bash
istioctl waypoint apply -n ambient-demo --enroll-namespace
```

This creates a `Gateway` named `waypoint` and its backing Envoy Deployment, and
labels the namespace so its services use the waypoint. Verify:

```bash
istioctl waypoint list -n ambient-demo
kubectl -n ambient-demo get pods -l gateway.networking.k8s.io/gateway-name=waypoint -o wide
kubectl get ns ambient-demo -L istio.io/use-waypoint
```

**Expected:** a `waypoint` pod (Envoy) running, and the namespace labeled to use
it. Now `httpbin` traffic flows `curl → ztunnel →(HBONE)→ waypoint →(HBONE)→
ztunnel → httpbin`.

## 2. Baseline through the waypoint — all methods work

```bash
kubectl -n ambient-demo exec deploy/curl -- \
  curl -s -o /dev/null -w "GET    -> %{http_code}\n" http://httpbin:8000/get
kubectl -n ambient-demo exec deploy/curl -- \
  curl -s -o /dev/null -w "DELETE -> %{http_code}\n" -X DELETE http://httpbin:8000/delete
```

**Expected:** both succeed (`200`).

## 3. Apply the L7 policy (GET only)

```bash
kubectl apply -f l7-policy.yaml
```

## 4. Test L7 enforcement

```bash
kubectl -n ambient-demo exec deploy/curl -- \
  curl -s -o /dev/null -w "GET    -> %{http_code}\n" http://httpbin:8000/get
kubectl -n ambient-demo exec deploy/curl -- \
  curl -s -o /dev/null -w "DELETE -> %{http_code}\n" -X DELETE http://httpbin:8000/delete
```

**Expected:**
- `GET` → `200`
- `DELETE` → `403` (denied by the waypoint's L7 RBAC)

This is the key contrast with Experiment 03: the decision now depends on the
**HTTP method**, which only the Envoy waypoint can see.

## 5. Inspect the waypoint like any Envoy

The waypoint is a normal Envoy, so `proxy-config` (not `ztunnel-config`) works:

```bash
WP=$(kubectl -n ambient-demo get pod -l gateway.networking.k8s.io/gateway-name=waypoint -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config listeners "$WP" -n ambient-demo
istioctl proxy-config routes    "$WP" -n ambient-demo
```

---

## What just happened

- `istioctl waypoint apply` deployed an **Envoy** proxy and told the namespace to
  route L7 traffic through it.
- ztunnel still does mTLS/L4, but now hands HTTP off to the waypoint over HBONE;
  the waypoint parses HTTP and enforced the **method-based** policy.
- You used `istioctl proxy-config` for the waypoint (Envoy) and
  `istioctl ztunnel-config` for ztunnel — two different proxies, two different
  tools.

## Cleanup

```bash
kubectl delete -f l7-policy.yaml
istioctl waypoint delete waypoint -n ambient-demo
kubectl label ns ambient-demo istio.io/use-waypoint- 2>/dev/null || true
```
