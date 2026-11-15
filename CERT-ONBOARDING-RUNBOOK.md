# Runbook: onboard one user with a certificate, then give access

**Cluster:** `kind-ops-lab` · **API server:** `https://127.0.0.1:51588` · **User:** maya · **Group:** `globex-devs` · **Namespace:** `team-globex`

What you will prove, in this order:

1. **Request**: the user makes a key and a CSR. The key never leaves her folder.
2. **Approve**: the admin checks what's *inside* the CSR, then approves. The cluster CA signs it.
3. **Authenticated, not authorized**: maya's kubeconfig works, the API server knows who she is, but `kubectl get no` is **Forbidden**.
4. **Authorized**: the admin adds namespace, quota and RBAC for the **group**, and the same commands start working.
5. **Limits**: what she still can't do.

**How to use it:** at each 🔮, write down your prediction *before* running. At each ✋, compare with the "Expect" line.

Two terminals:

| Terminal | Who | Rule |
|---|---|---|
| **A** | Admin | your normal kubeconfig (`kind-ops-lab`) |
| **M** | Maya | runs `export KUBECONFIG=~/maya-laptop/kubeconfig` and never uses the admin config |

---

## 0. Preflight (Terminal A)

```bash
kubectl config current-context        # Expect: kind-ops-lab
kubectl get csr                       # Expect: No resources found (or no "maya")
kubectl get ns team-globex            # Expect: NotFound (we create it in step 6)
```

If a `maya` CSR already exists from an earlier try: `kubectl delete csr maya`.

---

## 1. Maya: key and CSR (Terminal M)

```bash
mkdir -p ~/maya-laptop && cd ~/maya-laptop
openssl genrsa -out maya.key 2048
openssl req -new -key maya.key -out maya.csr -subj "/CN=maya/O=globex-devs"
openssl req -in maya.csr -noout -subject -verify
```

✋ **Expect:** `subject=CN=maya, O=globex-devs` and `verify OK` (proves she holds the private key).

🔮 Which of these two files may she send by email: `maya.key` or `maya.csr`? Why?

---

## 2. Admin: receive and submit the CSR (Terminal A)

```bash
mkdir -p ~/admin-inbox && cp ~/maya-laptop/maya.csr ~/admin-inbox/ && cd ~/admin-inbox   # "she sent it"

kubectl apply -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: { name: maya }
spec:
  request: $(base64 < maya.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 7776000        # 90 days
  usages: ["client auth"]
EOF
kubectl get csr maya
```

✋ **Expect:** `CONDITION Pending`, `REQUESTEDDURATION 90d`.

---

## 3. Admin: check what's inside, then approve (Terminal A)

The name `maya` in `kubectl certificate approve maya` is only the **object name**. Check the identity *inside*:

```bash
kubectl get csr maya -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -subject
kubectl get csr maya -o jsonpath='{.spec.username}{"\n"}'
```

✋ **Expect:** `subject=CN=maya, O=globex-devs`, and the submitter is you (`kubernetes-admin`).

🔮 What would you do if the subject said `O=system:masters`? (Answer: `kubectl certificate deny maya`, then delete it. Never approve.)

```bash
kubectl certificate approve maya
kubectl get csr maya
```

✋ **Expect:** `CONDITION Approved,Issued`.

---

## 4. Admin: extract the certificate and prepare the 3 public files (Terminal A)

```bash
cd ~/admin-inbox
kubectl get csr maya -o jsonpath='{.status.certificate}' | base64 -d > maya.crt
openssl x509 -in maya.crt -noout -subject -issuer -enddate

kubectl config view --raw --minify --context kind-ops-lab \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
kubectl config view --minify --context kind-ops-lab -o jsonpath='{.clusters[0].cluster.server}'; echo

cp maya.crt ca.crt ~/maya-laptop/      # "send" maya.crt + ca.crt + the server URL
```

✋ **Expect:**
- `subject=O=globex-devs, CN=maya`
- `issuer=CN=kubernetes` ← **the cluster CA signed it. It is not self-signed.**
- `notAfter` = about 90 days from now
- server URL `https://127.0.0.1:51588`

🔮 Is anything you just sent secret?

---

## 5. Maya: build her kubeconfig, and see that she is authenticated but has NO rights (Terminal M)

```bash
cd ~/maya-laptop
export KUBECONFIG=$PWD/kubeconfig
kubectl config set-cluster ops-lab --server=https://127.0.0.1:51588 --certificate-authority=ca.crt --embed-certs=true
kubectl config set-credentials maya --client-key=maya.key --client-certificate=maya.crt --embed-certs=true
kubectl config set-context globex --cluster=ops-lab --user=maya --namespace=team-globex
kubectl config use-context globex
chmod 600 kubeconfig
kubectl config get-contexts           # only "globex" should exist in this file
```

🔮 Before running the next block: which of these will work?

```bash
kubectl auth whoami
kubectl get no
kubectl get pods
```

✋ **Expect:**
- `auth whoami` **works**: `Username maya`, `Groups [globex-devs system:authenticated]`. The API server **trusts the certificate** (authentication OK).
- `get no` → `Forbidden: User "maya" cannot list resource "nodes" ... at the cluster scope`
- `get pods` → `Forbidden ... in the namespace "team-globex"`

**That's the key lesson:** a valid certificate only proves **who** she is. **What** she may do comes from RBAC, and she has none yet.
(`whoami` works because every authenticated user may ask "who am I?".)

---

## 6. Admin: give the GROUP its space and rights (Terminal A)

```bash
# namespace
kubectl create namespace team-globex
kubectl label namespace team-globex tenant=globex \
  pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/warn=restricted

# quota + defaults
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata: { name: globex-quota, namespace: team-globex }
spec:
  hard: { requests.cpu: "4", requests.memory: 8Gi, limits.cpu: "8", limits.memory: 16Gi, pods: "20",
          services.loadbalancers: "0", services.nodeports: "0" }
---
apiVersion: v1
kind: LimitRange
metadata: { name: globex-defaults, namespace: team-globex }
spec:
  limits:
  - type: Container
    defaultRequest: { cpu: 100m, memory: 128Mi }
    default:        { cpu: 500m, memory: 512Mi }
EOF

# rights in the namespace (to the group)
kubectl create rolebinding globex-devs-edit -n team-globex --clusterrole=edit --group=globex-devs

# rights to see nodes (cluster-scoped, so it needs a ClusterRole + ClusterRoleBinding)
kubectl create clusterrole node-viewer --verb=get,list,watch --resource=nodes
kubectl create clusterrolebinding globex-devs-node-viewer --clusterrole=node-viewer --group=globex-devs

# check as maya, from the admin side
kubectl auth can-i list nodes --as=maya --as-group=globex-devs                          # yes
kubectl auth can-i create deployments -n team-globex --as=maya --as-group=globex-devs   # yes
```

🔮 Did you touch maya's certificate or kubeconfig in this step? Why does it still change what she can do?

---

## 7. Maya: the same commands now work (Terminal M)

```bash
kubectl get no
kubectl create deployment web --image=nginx:1.27 --replicas=2
kubectl rollout status deploy/web
kubectl get pods
kubectl describe resourcequota
```

✋ **Expect:**
- `get no` lists `ops-lab-control-plane`
- 2 `web` pods `Running` in `team-globex`
- quota shows `requests.cpu 200m/4`, `pods 2/20` (the LimitRange added 100m per pod)

---

## 8. Maya: what she must NOT be able to do (Terminal M)

```bash
kubectl get pods -n kube-system               # Forbidden: other namespace
kubectl delete resourcequota globex-quota     # Forbidden: "edit" can't change quota
kubectl delete node ops-lab-control-plane     # Forbidden: node-viewer is read-only
kubectl create rolebinding me-admin --clusterrole=admin --user=maya   # Forbidden: "edit" can't manage RBAC
kubectl scale deploy/web --replicas=50        # accepted, but only up to 20 pods run (quota)
kubectl get events --field-selector reason=FailedCreate | tail -3      # "exceeded quota"
kubectl scale deploy/web --replicas=2
```

✋ **Expect:** four `Forbidden`, then the scale is accepted but the ReplicaSet stops at the pod quota with `exceeded quota` events.

---

## 9. Bonus: a second developer with zero RBAC work

Repeat steps 1–5 for **raj** (`/CN=raj/O=globex-devs`, folder `~/raj-laptop`, CSR name `raj`).

🔮 Will raj's `kubectl get no` work right away? Why?
✋ **Expect:** yes. The bindings are on the group `globex-devs`, and raj's certificate carries that group.

---

## 10. Cleanup (Terminal A)

```bash
kubectl delete namespace team-globex
kubectl delete clusterrolebinding globex-devs-node-viewer
kubectl delete clusterrole node-viewer
kubectl delete csr maya raj --ignore-not-found
rm -rf ~/maya-laptop ~/raj-laptop ~/admin-inbox
```

In Terminal M: `unset KUBECONFIG` (or just close it).

---

## What to say when you're done (summary)

- The **user** makes the key and the CSR. The key never leaves her machine.
- The **admin** checks the CN and O **inside** the CSR object, approves, and sends back 3 public files: `maya.crt`, `ca.crt`, the server URL.
- The **cluster CA** signs the certificate (`issuer=CN=kubernetes`). It is not self-signed.
- A certificate gives **authentication only**. **Authorization** comes from RBAC bound to the **group**, so new team members need no RBAC change.
- Weak points: no revocation, manual renewal before `notAfter`, and identity checks done by hand. This is why people use OIDC in production.
