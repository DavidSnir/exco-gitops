# EXCO DevOps Exercise — Tiny service → local cluster → GitOps deployment

A deliberately small web service, taken from source code to a running deployment on a
local Kubernetes cluster, the GitOps way.

**Repo:** [DavidSnir/exco-gitops](https://github.com/DavidSnir/exco-gitops) (public)
**Status:** Part 0 complete. Parts 1–3 and bonuses are planned, not implemented.
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
| [Terraform](https://terraform.io) | 1.16.6 | Cluster + Argo CD as code. Installed from HashiCorp releases, *not* Homebrew — see §3. |
| [Helm](https://helm.sh) | 4.3.0 | Installs Argo CD from the official `argo-helm` chart. |
| [Argo CD](https://argo-cd.readthedocs.io) | chart-pinned | GitOps sync engine. Watches `k8s/` and applies what it finds. |
| Ingress controller | TBD | Select a maintained controller with Ingress support during Part 1. |
| GitHub Actions | — | CI on push to `main`. |
| GHCR | — | Image registry that needs no separate credentials setup, and sits next to the repo. |
| `yq` | 4.54.1 | Rewrites the image tag in CI without needing a full YAML round-trip. |
| Node.js 22 (alpine) | — | The service. No dependencies or build step; runs as the built-in non-root `node` user. |
| Visual Studio Code | installed | Editor available on the laptop. |

### Steps

**Part 0 — setup and plan**
1. Install tooling.
2. Log in to GitHub, create the repo.
3. Write this README up front, keep it updated, commit it along with everything else.
4. Write the service: `GET /`, `GET /healthz` → 200.
5. Dockerfile, non-root. Build and run locally to prove it works.

**Part 1 — cluster as code**
6. Terraform creates the kind cluster from a declarative `kind.yaml` (3 nodes).
7. Terraform installs Argo CD and the ingress controller.
8. `terraform destroy` tears it all back down.

**Part 2 — GitOps deployment**
9. Move the app manifests into `k8s/` in this repo. That directory is the source of truth.
10. Terraform creates the ArgoCD `Application` CR pointing at `k8s/` — the handoff from Terraform to GitOps.
11. Deployment with 2 replicas, readiness + liveness probes, requests **and** limits.
12. Service + Ingress. Configure kind port mappings and controller routing so the app opens
    at `http://localhost:8080` in the browser.

**Part 3 — CI/CD**
13. GitHub Actions on push to `main`: build → push to GHCR as `sha-<short>` → rewrite the image
    tag in `k8s/deployment.yaml` → commit back to `main`.
14. Argo CD auto-syncs and rolls out. **No `kubectl` in CI.**
15. Prove zero downtime: change the message, push, hammer the endpoint in a loop, count failures.

**Bonus**
16. HPA (min 2 / max 5) + metrics-server.
17. Prometheus + Grafana, installed by Argo CD.

### Key design decision

**Who owns what.** Terraform owns the cluster, Argo CD and the ingress controller, matching Part 1.
Argo CD owns the app manifests. Avoid having Terraform and Argo CD manage the same resources.

---

## 2. Repository layout

Target layout; only `app/`, `.gitignore` and this README are committed so far.

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
- `brew install terraform` failed because the formula was unavailable. Installed the official
  binary from `releases.hashicorp.com` into `/usr/local/bin` instead.
- GitHub login initially failed to persist because `~/.config` was root-owned. Fixed ownership
  of that directory, then repeated login successfully as `DavidSnir`.
- Created the public `DavidSnir/exco-gitops` repository. Subsequent commits use the GitHub
  noreply identity; the first commit used a temporary local identity (history preserved).
- Service runs, both routes return what they should, container runs as `uid=1000(node)`.
- Verified graceful shutdown: `docker stop` → SIGTERM → drain → **exit code 0**.

---

## 4. How to use it

### Run the service locally

```sh
docker build -t exco-app:dev --build-arg APP_VERSION=dev app/
docker run -d --name exco-local -p 18080:8080 exco-app:dev
curl -fsS http://localhost:18080/
curl -fsS http://localhost:18080/healthz
docker exec exco-local id  # uid=1000(node), not root
docker stop --time 15 exco-local
docker logs exco-local    # SIGTERM handled, connections drained
docker rm exco-local
```

Open `http://localhost:18080` in a browser while the container is running.
Alternatively: `cd app && npm start` (no dependency installation required).

### AI correction

The AI said the CLI login needed `write:packages` for GitHub Actions to push to GHCR.
That conflates local CLI authentication with workflow authentication. The planned workflow
will use its own `GITHUB_TOKEN` with `packages: write`; no extra CLI scope is needed for CI.
Code review also caught that `draining` was never set to true in the shutdown handler;
fixed it. Graceful shutdown alone does not prove zero-downtime Kubernetes rollouts:
endpoint propagation and traffic draining still need configuration and testing in Part 3.

---

## 5. What I'd change for EKS in production

_(written at the end)_
