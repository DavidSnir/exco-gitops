# EXCO DevOps Exercise

[GitHub repository](https://github.com/DavidSnir/exco-gitops)

## Plan and tools

1. **Part 0:** Set up tools and GitHub; build and test a small Node.js service in a non-root container.
2. **Part 1:** Use Terraform to create a kind cluster (1 control-plane, 2 workers) and install Argo CD and Traefik with Helm.
3. **Part 2:** Have Argo CD render the Helm chart in `k8s/` and sync two replicas, probes, resource requests/limits, Service and Ingress.
4. **Part 3:** Use GitHub Actions to push commit-SHA images to GHCR and update the image tag in git. Test a rollout with a request loop; no deployment commands from CI.
5. **If time permits:** HPA, Prometheus/Grafana through Argo CD, and production EKS notes.

Tools: Docker Desktop, kind, Terraform, Helm, kubectl, git, GitHub CLI, `yq`, and VS Code. The service uses Node.js 22 without dependencies.

## Current status

- **Parts 0–1 complete:** Service and non-root container tested. Terraform apply, destroy, and recreation verified; cluster left running.
- **Part 2 complete:** Argo CD renders the Helm chart from git and reports Synced/Healthy. Two ready non-root replicas run across the workers, with probes and resource budgets. App opens at http://localhost:18080 through Ingress.
- **Not done:** CI/CD and GHCR publishing, automatic image-tag updates in git, zero-downtime demonstration, HPA, monitoring, and production EKS notes.

Verified: both Helm charts lint successfully, GitOps/app acceptance checks pass, all three routes return 200, and 20 requests reached both replicas (10 each). Terraform reports no changes. This is a steady-state check, not yet the zero-downtime rollout demonstration.

## Repository

```text
app/                         Node.js service and Dockerfile (port 8090)
k8s/                         Helm app chart: templates and values.yaml, rendered by Argo CD
terraform/                   kind, Argo CD, Traefik and Application bootstrap chart
scripts/load-local-image.sh  Build the manifest's source revision and load it into kind
scripts/check-part2.sh       GitOps and app acceptance checks
```

## Run locally

```sh
docker build -t exco-app:dev --build-arg APP_VERSION=dev app/
docker run -d --name exco-local -p 127.0.0.1:18082:8090 exco-app:dev
curl -fsS http://localhost:18082/
curl -fsS http://localhost:18082/healthz
docker exec exco-local id
docker stop --time 15 exco-local
docker rm exco-local
```

## Cluster and GitOps

Run from the repository root with Docker Desktop running. Ports 18080 and 18081 are used because 8080 and 8081 are occupied. Push the app manifests to `main` so Argo CD can read them.

```sh
umask 077
terraform -chdir=terraform init
terraform -chdir=terraform plan
terraform -chdir=terraform apply
sh scripts/load-local-image.sh
export KUBECONFIG="$PWD/terraform/kubeconfig"
kubectl -n argocd get application exco
kubectl -n exco get deployment,pods,service,ingress
sh scripts/check-part2.sh
EXPECTED_HTTP_STATUS=200 sh terraform/check.sh
curl -fsS http://localhost:18080/
```

Once synced and healthy, open **http://localhost:18080**. Traffic goes through Traefik; no app port-forward is needed. Argo CD auto-syncs, prunes and self-heals from `k8s/` on `main`.

Edit image tags, replicas and resource budgets in `k8s/values.yaml`, then commit and push. Preview without deploying:

```sh
helm lint k8s
helm template exco-app k8s --namespace exco
```

Argo CD renders Helm templates and manages the app resources; it does not create an app Helm release. Use Argo CD for app status, not `helm list`.

Part 2 uses a SHA-tagged image loaded into kind from its exact source commit. Fresh clusters need the load step; pods may show ImagePullBackOff until it completes and Kubernetes retries. GHCR replaces local image loading in Part 3.

To open Argo CD:

```sh
kubectl -n argocd port-forward svc/argocd-server 18081:443 --address 127.0.0.1
```

Open **https://localhost:18081**, accept the self-signed certificate, and log in as `admin`. Retrieve the password in another terminal:

```sh
kubectl --kubeconfig terraform/kubeconfig -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
```

State, kubeconfig and passwords contain credentials; keep them out of git.

To remove the exercise cluster and everything inside it (do not run at handoff):

```sh
terraform -chdir=terraform destroy
```

## Decision

Terraform owns the cluster, platform components and bootstrap Application; Argo CD owns the app Deployment, Service and Ingress. This keeps the same resources from being managed by two tools.

## AI correction

The AI suggested ingress-nginx. Checking the official Kubernetes retirement announcement showed support ended in March 2026, so we chose Traefik instead.
