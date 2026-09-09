# Experiment 02 — Prove mTLS over HBONE

**Goal:** show that traffic between enrolled pods is transparently
**mTLS-encrypted and tunneled over HBONE** — and inspect the SPIFFE identities
and certificates ztunnel uses.

**Prereqs:** Experiment 01 done (namespace `ambient-demo` enrolled).

---

## 1. Confirm the identities ztunnel holds

```bash
istioctl ztunnel-config certificates | grep ambient-demo
```

**Expected:** X.509 leaf certs for the SPIFFE identities of your workloads, e.g.

```
spiffe://cluster.local/ns/ambient-demo/sa/curl
spiffe://cluster.local/ns/ambient-demo/sa/httpbin
```

Get the full detail (validity, serial, state) as JSON:

```bash
istioctl ztunnel-config certificates -o json | \
  jq -r '.[] | .identity' | sort -u
```

These certs are issued by istiod (the CA) and are short-lived — ztunnel rotates
them automatically.

## 2. Watch the HBONE tunnel carry a request

Follow the ztunnel on the **source** pod's node. First find where `curl` runs:

```bash
CURL_NODE=$(kubectl -n ambient-demo get pod -l app=curl -o jsonpath='{.items[0].spec.nodeName}')
ZT=$(kubectl -n istio-system get pod -l app=ztunnel \
       --field-selector spec.nodeName=$CURL_NODE -o jsonpath='{.items[0].metadata.name}')
echo "curl node=$CURL_NODE  ztunnel=$ZT"
kubectl -n istio-system logs "$ZT" -f &
```

Now send a request:

```bash
kubectl -n ambient-demo exec deploy/curl -- curl -s http://httpbin:8000/get >/dev/null
```

**Expected:** an access-log line from ztunnel describing the connection with:
- source identity `.../sa/curl` and destination identity `.../sa/httpbin`,
- direction (outbound on the source node),
- bytes sent/received.

Stop the background log follow with `kill %1` when done.

## 3. See the destination side and the tunnel port

The destination node's ztunnel terminates the HBONE tunnel on **:15008**. Find
it and look at its inbound logs:

```bash
HB_NODE=$(kubectl -n ambient-demo get pod -l app=httpbin -o jsonpath='{.items[0].spec.nodeName}')
ZT_IN=$(kubectl -n istio-system get pod -l app=ztunnel \
          --field-selector spec.nodeName=$HB_NODE -o jsonpath='{.items[0].metadata.name}')
kubectl -n istio-system logs "$ZT_IN" --tail=20
```

If `curl` and `httpbin` happen to be on the **same** node, both sides are the
same ztunnel pod — scale httpbin or delete/recreate a pod to spread them across
nodes if you want to see the cross-node case (that's why the lab cluster has 2
workers).

## 4. (Optional) Show that plaintext is refused

Application traffic is captured and wrapped in mTLS automatically — an attacker
on the pod network cannot speak plaintext to the workload's mesh port. You can
demonstrate the tunnel port only speaks HBONE/mTLS, not plain HTTP:

```bash
# Try to talk plain HTTP to a ztunnel HBONE port -> it will NOT serve your app.
kubectl -n ambient-demo exec deploy/curl -- \
  sh -c 'curl -s -m 3 http://httpbin:15008/ || echo "no plaintext on HBONE port (expected)"'
```

---

## What just happened

- Every enrolled workload has a **SPIFFE identity** backed by an istiod-issued
  X.509 cert (step 1).
- When `curl` called `httpbin`, its traffic was captured by the node's ztunnel,
  wrapped in **mTLS**, and carried to the destination node's ztunnel as an
  **HTTP/2 CONNECT (HBONE) on :15008** (steps 2–3).
- The application saw a normal TCP/HTTP call; the encryption and identity
  handling were entirely transparent.

## Notes

- Log formats/fields differ between Istio versions — look for the two SPIFFE
  identities and the byte counts rather than an exact string.
- Bump verbosity if you want more detail:
  `istioctl ztunnel-config log "$ZT" --level debug` (reset with `--level info`).
