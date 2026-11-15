# tenant-rbac-lab

Hands-on Kubernetes multi-tenancy lab on a local [kind](https://kind.sigs.k8s.io/) cluster: tenant namespaces, real x509 users through the CSR API, RBAC, ResourceQuota, LimitRange, Pod Security Admission and NetworkPolicy. Every step has an "expect" line, so you can predict the result before you run it.

**Read it as a website:** https://infra-ops-lab.github.io/tenant-rbac-lab/

[![docs](https://github.com/infra-ops-lab/tenant-rbac-lab/actions/workflows/docs.yml/badge.svg)](https://github.com/infra-ops-lab/tenant-rbac-lab/actions/workflows/docs.yml)

## Runbooks

| Runbook | What you build | Web view |
|---|---|---|
| [RUNBOOK.md](RUNBOOK.md) | Tenant **acme** with `acme-dev` + `acme-prod`: users alice/bob/carol, CI ServiceAccount, RBAC, quota, limits, PSA, NetworkPolicy, then break it on purpose | [open](https://infra-ops-lab.github.io/tenant-rbac-lab/RUNBOOK/) |
| [CERT-ONBOARDING-RUNBOOK.md](CERT-ONBOARDING-RUNBOOK.md) | One user (**maya**) from key → CSR → approval → kubeconfig: authenticated but Forbidden first, then authorized through her group | [open](https://infra-ops-lab.github.io/tenant-rbac-lab/CERT-ONBOARDING-RUNBOOK/) |

## Repository layout

```
RUNBOOK.md                   tenant onboarding runbook (steps 1-13 + interview questions)
CERT-ONBOARDING-RUNBOOK.md   single-user certificate onboarding runbook
manifests/platform/          applied as cluster admin (objects carry their namespace)
manifests/tenant/            applied as the tenant user with -n <ns> (no namespace in the files)
scripts/make-user.sh         x509 user through the CSR API -> kubeconfig context <user>@ops-lab
scripts/check-rbac.sh        kubectl auth can-i matrix with expected answers
scripts/docs-prepare.sh      assembles the website source (used by CI)
mkdocs.yml                   website config (MkDocs Material)
.github/workflows/docs.yml   builds the website and publishes it to GitHub Pages
```

## Quick start

Needs a kind cluster with the context `kind-ops-lab`, plus `kubectl` and `openssl`.

```bash
git clone https://github.com/infra-ops-lab/tenant-rbac-lab.git ~/tenant-rbac-lab
export LAB=~/tenant-rbac-lab

$LAB/scripts/make-user.sh alice acme-admins
$LAB/scripts/make-user.sh bob   acme-devs
kubectl apply -f $LAB/manifests/platform/
$LAB/scripts/check-rbac.sh
```

Then follow [RUNBOOK.md](RUNBOOK.md) from step 5. To learn step by step, apply the files one at a time instead.

## Credentials stay local

`scripts/make-user.sh` writes private keys, certificates and CSRs to `certs/`. That folder, every `*.key` / `*.crt` / `*.csr` / `*.pem` file and every kubeconfig file are in [.gitignore](https://github.com/infra-ops-lab/tenant-rbac-lab/blob/main/.gitignore). Never commit them: a client certificate cannot be revoked before it expires.

## Preview the website locally

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-docs.txt
scripts/docs-prepare.sh && .venv/bin/mkdocs serve      # http://127.0.0.1:8000
```

The site rebuilds automatically on every push to `main` that touches the docs.
