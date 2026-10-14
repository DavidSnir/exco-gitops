# EXCO DevOps Exercise — Tiny service → local cluster → GitOps deployment

A deliberately small web service, taken from source code to a running deployment on a
local Kubernetes cluster, the GitOps way.

**Repo:** `exco-gitops` (public)
**Service:** `app/` — Node.js, standard library only, no dependencies
**Cluster:** 3-node [kind](https://kind.sigs.k8s.io) cluster (1 control-plane + 2 workers)
**Delivery:** GitHub Actions → GHCR → commit the image tag back to git → Argo CD rolls it out

---

## 1. Plan

### Tools chosen

| Tool | Version | Why this one |
|---|---|---|
| Docker Desktop | 4.95.0 | Already running on the laptop; kind needs it. No extra VM layer. |
| [kind](https://kind.sigs.k8s.io) | 0.33.0 | Real kubeadm Kubernetes (real etcd, real kubelet) as containers. Most standard "local k8s" story, and the node count maps literally onto the 1 control-plane + 2 worker requirement. |
| [Terraform](https://terraform.io) | 1.16.6 | Cluster + Argo CD as code. Installed from HashiCorp releases, *not* Homebrew — see §5. |
| [Helm](https://helm.sh) | 4.3.0 | Installs Argo CD from the official `argo-helm` chart. |
| [Argo CD](https://argo-cd.readthedocs.io) | chart-pinned | GitOps sync engine. Watches `k8s/` and applies what it finds. |
| ingress-nginx | chart-pinned | The Ingress controller. |
| GitHub Actions | — | CI on push to `main`. |
| GHCR | — | Image registry that needs no separate credentials setup, and sits next to the repo. |
| `yq` | 4.54.1 | Rewrites the image tag in CI without needing a full YAML round-trip. |
| Node.js 22 (alpine) | — | The service. Zero dependencies ⇒ no `node_modules` ⇒ nothing root-owned ⇒ genuinely clean non-root image. |

### Steps

**Part 0 — setup and plan**
1. Install tooling.
2. Log in to GitHub, create the repo.
3. Write this README up front, keep it updated, commit it along with everything else.
4. Write the service: `GET /`, `GET /healthz` → 200.
5. Dockerfile, non-root. Build and run locally to prove it works.

**Part 1 — cluster as code**
6. Terraform creates the kind cluster from a declarative `kind.yaml` (3 nodes).
7. Terraform installs Argo CD.
8. `terraform destroy` tears it all back down.

**Part 2 — GitOps deployment**
9. Move the app manifests into `k8s/` in this repo. That directory is the source of truth.
10. Terraform creates the ArgoCD `Application` CR pointing at `k8s/` — the handoff from Terraform to GitOps.
11. Deployment with 2 replicas, readiness + liveness probes, requests **and** limits.
12. Service + Ingress. ingress-nginx pinned to the control-plane node via `hostPort`, and the
    control-plane node publishes container port 80 to `127.0.0.1:8080`. Opens in the browser.

**Part 3 — CI/CD**
13. GitHub Actions on push to `main`: build → push to GHCR as `sha-<short>` → rewrite the image
    tag in `k8s/deployment.yaml` → commit back to `main`.
14. Argo CD auto-syncs and rolls out. **No `kubectl` in CI.**
15. Prove zero downtime: change the message, push, hammer the endpoint in a loop, count failures.

**Bonus**
16. HPA (min 2 / max 5) + metrics-server.
17. Prometheus + Grafana, installed by Argo CD.

### Key design decision

**Who owns what.** Terraform owns *bootstrap only* — the cluster and Argo CD itself, because Argo
CD obviously cannot sync itself before it exists. Everything else, including ingress-nginx, is owned
by Argo CD. This is the standard split, and it means after the initial `terraform apply`, the only
thing that mutates the cluster is git.

---

## 2. Repository layout

```
app/                      the service
  server.js               GET /, GET /healthz, GET /readyz, graceful shutdown
  Dockerfile              non-root (uid 1000, node)
k8s/                      GitOps source of truth — Argo CD reads this
terraform/                cluster + Argo CD, as code
.github/workflows/        CI/CD
Makefile                  convenience targets
```

---

## 3. Running notes

Updated as work progresses.

### Part 0

- Installed `terraform kind helm gh yq`. `gh` was already present but not linked on `PATH`.
- **Terraform is no longer in Homebrew core** (HashiCorp moved it to the BUSL licence and pulled it).
  Installed the official binary from `releases.hashicorp.com` into `/usr/local/bin`.
- Service runs, both routes return what they should, container runs as `uid=1000(node)`.
- Verified graceful shutdown: `docker stop` → SIGTERM → drain → **exit code 0**.

---

## 4. How to use it

_(filled in once the pieces exist)_

---

## 5. What I'd change for EKS in production

_(written at the end)_