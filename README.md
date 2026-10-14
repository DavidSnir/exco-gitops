# EXCO DevOps Exercise — Tiny service → local cluster → GitOps deployment

A deliberately small web service, taken from source code to a running deployment on a
local Kubernetes cluster, the GitOps way.

**Repo:** [DavidSnir/exco-gitops](https://github.com/DavidSnir/exco-gitops) (public)
**Status:** Part 0 complete. Part 1 implemented, validation in progress. Parts 2–3 and bonuses are not implemented.
**Service:** `app/` — Node.js, standard library only, no dependencies
**Cluster:** 3-node [kind](https://kind.sigs.k8s.io) cluster (1 control-plane + 2 workers)
**Delivery:** GitHub Actions → GHCR → commit the image tag back to git → Argo CD rolls it out

---

## 1. Plan

### Tools chosen

| Tool | Version | Why this one |
|---|---|---|
| Docker Desktop | 4.95.0 | Already running on the laptop; kind needs it. No extra VM layer. |
| [kind](https://kind.sigs.k8s.io) | CLI 0.33.0 / Terraform provider 0.11.0 | Real kubeadm Kubernetes as Docker containers; the provider embeds kind 0.31.0 rather than calling the installed CLI. Kubernetes image pinned to 1.35.8 and its digest. |
| [Terraform](https://terraform.io) | 1.16.6 | Cluster + Argo CD as code. Installed from HashiCorp releases, *not* Homebrew — see §3. |
| [Helm](https://helm.sh) | CLI 4.3.0 / Terraform provider 3.3.0 | Terraform uses the provider's embedded Helm library; the CLI is for inspection. |
| [Argo CD](https://argo-cd.readthedocs.io) | chart 10.10.3 / app 3.5.5 | GitOps sync engine; app integration comes in Part 2. |
| [Traefik](https://traefik.io/) | chart 41.7.1 / app 3.7.14 | Maintained controller supporting standard Kubernetes Ingress; ingress-nginx retired in March 2026. |
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
6. Terraform creates the kind cluster from declarative HCL (3 nodes), using a native provider.
7. Terraform installs Argo CD and the ingress controller.
8. `terraform destroy` tears it all back down.

**Part 2 — GitOps deployment**
9. Move the app manifests into `k8s/` in this repo. That directory is the source of truth.
10. Terraform creates the ArgoCD `Application` CR pointing at `k8s/` — the handoff from Terraform to GitOps.
11. Deployment with 2 replicas, readiness + liveness probes, requests **and** limits.
12. Service + Ingress. Configure kind port mappings and controller routing so the app opens
    at `http://localhost:18080` in the browser (8080 is already occupied).

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

**Native Terraform resources rather than shell provisioners.** The community `tehcyx/kind`
provider handles cluster creation/deletion; `hashicorp/helm` manages the two chart releases.
Helm gets endpoint and PEM credentials directly from the cluster's computed attributes so
the first plan does not require an existing kubeconfig. Explicit dependencies order creation
and destruction, and cluster replacement also replaces both releases. Tradeoff: a community
provider is another dependency, and changing kind's node configuration recreates the cluster.

**Local networking.** Docker Desktop maps `127.0.0.1:18080` to the control-plane's NodePort
`30080`. Traefik's Service uses `externalTrafficPolicy: Cluster` to reach a controller pod
on either worker. No cloud load balancer, host networking, tunnel, or `/etc/hosts` edits.

---

## 2. Repository layout

`app/` and `terraform/` are implemented. App manifests and CI are planned for later parts.

```
app/                      the service
  server.js               GET /, GET /healthz, GET /readyz, graceful shutdown
  Dockerfile              non-root (uid 1000, node)
k8s/                      GitOps source of truth — Argo CD reads this
terraform/                cluster + Argo CD + Traefik, as code
  values/                 version-controlled Helm values
.github/workflows/        CI/CD
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

### Part 1

- Docker Desktop has about 8 GiB of VM memory available; use non-HA Argo CD and small
  explicit resource budgets. Disable Dex, notifications and ApplicationSet replicas for now.
- Ports 8080 and 8081 are occupied by an existing process; use 18080 and 18081 instead.
- Terraform `init`, `validate` and the fresh plan pass; plan contains three resources:
  the kind cluster and two Helm releases. Live create/destroy/recreate checks pending.

---

## 4. How to use it

### Run the service locally

```sh
docker build -t exco-app:dev --build-arg APP_VERSION=dev app/
docker run -d --name exco-local -p 127.0.0.1:18082:8080 exco-app:dev
curl -fsS http://localhost:18082/
curl -fsS http://localhost:18082/healthz
docker exec exco-local id  # uid=1000(node), not root
docker stop --time 15 exco-local
docker logs exco-local    # SIGTERM handled, connections drained
docker rm exco-local
```

Open `http://localhost:18082` in a browser while the container is running.
Alternatively: `cd app && npm start` (no dependency installation required).

### Create or destroy the local cluster

Prerequisites: Docker Desktop running, Terraform installed, and a free TCP port 18080.
Run commands as your normal Mac user, not root.

```sh
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan
terraform -chdir=terraform apply

export KUBECONFIG="$PWD/terraform/kubeconfig"
kubectl get nodes -o wide
kubectl get pods -n argocd
kubectl get pods -n traefik
helm list -A
curl -i http://localhost:18080  # 404 is expected until Part 2 adds a route

# Destructive: removes this exercise cluster and everything inside it.
terraform -chdir=terraform destroy
```

One ordinary apply bootstraps everything; no `-target` or manual Helm installs.
To change the local HTTP port, use `-var='app_port=18090'` consistently for plan/apply;
the kind cluster must be recreated to change Docker port mappings.

State and kubeconfig contain credentials: they are gitignored and must stay local.
The provider lock file is committed. Docker image caches and the shared Docker `kind`
network may remain after destroy; the exercise's three node containers must be gone.

### Open Argo CD

```sh
export KUBECONFIG="$PWD/terraform/kubeconfig"
kubectl -n argocd port-forward svc/argocd-server 18081:443 --address 127.0.0.1
```

Open **https://localhost:18081**, accept the local self-signed certificate warning,
and log in as `admin`. In another terminal, retrieve the initial password locally:

```sh
kubectl --kubeconfig terraform/kubeconfig -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
```

Do not commit the password or include it in screenshots. Stop port-forward with Ctrl+C.
Authentication and TLS are left enabled; the UI is not exposed through ingress.

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
