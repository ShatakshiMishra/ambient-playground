# Experiment 03 — L4 authorization enforced by ztunnel

**Goal:** enforce an `AuthorizationPolicy` at **L4 by identity** — allow only the
`curl` service account to reach `httpbin`, deny everyone else — with **no
waypoint and no sidecars**. This is a headline ambient feature: zero-trust L4
authz from ztunnel alone.

**Prereqs:** Experiment 01 done (namespace enrolled).

---

## 1. Add a second client with a different identity

We need a "not curl" caller to prove the deny path. Deploy a second client under
its own service account:

```bash
kubectl -n ambient-demo create serviceaccount intruder
kubectl -n ambient-demo run intruder --image=curlimages/curl:8.10.1 \
  --overrides='{"spec":{"serviceAccountName":"intruder"}}' \
  --command -- sleep infinity
kubectl -n ambient-demo wait --for=condition=Ready pod/intruder --timeout=60s
```

## 2. Baseline — everyone can reach httpbin

```bash
kubectl -n ambient-demo exec deploy/curl -- \
  curl -s -o /dev/null -w "curl     -> %{http_code}\n" http://httpbin:8000/get
kubectl -n ambient-demo exec intruder -- \
  curl -s -o /dev/null -w "intruder -> %{http_code}\n" http://httpbin:8000/get
```

**Expected:** both print `200`.

## 3. Apply the L4 policy (allow only curl)

```bash
kubectl apply -f allow-curl.yaml
istioctl ztunnel-config all -o json | jq '.policies // .authorizationPolicies' | head
```

Give ztunnel a moment to receive the policy over xDS (a few seconds).

## 4. Test enforcement

```bash
kubectl -n ambient-demo exec deploy/curl -- \
  curl -s -o /dev/null -w "curl     -> %{http_code}\n" http://httpbin:8000/get
kubectl -n ambient-demo exec intruder -- \
  curl -s -m 5 -o /dev/null -w "intruder -> %{http_code}\n" http://httpbin:8000/get || \
  echo "intruder -> connection denied/reset (expected)"
```

**Expected:**
- `curl` still gets `200`.
- `intruder` is **denied** — the connection is reset/closed by ztunnel because
  its SPIFFE identity (`.../sa/intruder`) is not in the allow list. You'll see a
  non-200 / connection error.

Confirm from the destination ztunnel's logs that the deny happened at L4:

```bash
HB_NODE=$(kubectl -n ambient-demo get pod -l app=httpbin -o jsonpath='{.items[0].spec.nodeName}')
ZT_IN=$(kubectl -n istio-system get pod -l app=ztunnel \
          --field-selector spec.nodeName=$HB_NODE -o jsonpath='{.items[0].metadata.name}')
kubectl -n istio-system logs "$ZT_IN" --tail=30 | grep -i -E 'deny|rbac|intruder' || true
```

---

## What just happened

- The policy selects `httpbin` and allows only the `curl` **principal**
  (SPIFFE identity). ztunnel authenticated each caller via mTLS, so it can match
  on identity, not just IP.
- Because the rule is purely L4 (no HTTP paths/methods/headers), **ztunnel
  enforces it directly** — no Envoy, no waypoint needed.
- `intruder`, presenting a different identity, was rejected before its bytes ever
  reached the httpbin pod.

## Try next

- Change `principals` to a `namespaces` or `notPrincipals` condition and re-test.
- Add an L7 condition (e.g. `to.operation.paths: ["/get"]`). ztunnel **cannot**
  enforce L7 — that requires a waypoint, which is exactly Experiment 04.

## Cleanup

```bash
kubectl delete -f allow-curl.yaml
kubectl -n ambient-demo delete pod intruder
kubectl -n ambient-demo delete serviceaccount intruder
```
