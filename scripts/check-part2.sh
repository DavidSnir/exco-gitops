#!/bin/sh
# Read-only checks of git reconciliation, app health and the ingress endpoint.
set -eu

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
export KUBECONFIG
KUBECONFIG=$(terraform -chdir="$repo_dir/terraform" output -raw kubeconfig_path)
app_url=$(terraform -chdir="$repo_dir/terraform" output -raw app_url)

kubectl -n argocd wait --for='jsonpath={.status.sync.status}=Synced' application/exco --timeout=240s
kubectl -n argocd wait --for='jsonpath={.status.health.status}=Healthy' application/exco --timeout=240s
kubectl -n exco rollout status deployment/exco-app --timeout=180s

kubectl -n exco get deployment exco-app -o json | jq -e '
  .spec.replicas == 2 and
  .status.availableReplicas == 2 and
  .status.updatedReplicas == 2 and
  .spec.template.spec.securityContext.runAsNonRoot == true and
  (.spec.template.spec.containers[0] |
    .readinessProbe.httpGet.path == "/readyz" and
    .livenessProbe.httpGet.path == "/healthz" and
    .resources.requests.cpu != null and .resources.requests.memory != null and
    .resources.limits.cpu != null and .resources.limits.memory != null)
' >/dev/null
kubectl -n exco get endpointslices -l kubernetes.io/service-name=exco-app -o json | jq -e '
  [.items[].endpoints[] | select(.conditions.ready == true)] | length == 2
' >/dev/null
test "$(kubectl -n exco exec deployment/exco-app -- id -u)" = 1000

curl --max-time 10 -fsS "$app_url/" | jq -e '.message and .version and .pod'
curl --max-time 10 -fsS "$app_url/healthz" | jq -e '.status == "ok"'
curl --max-time 10 -fsS "$app_url/readyz" | jq -e '.status == "ready"'
kubectl -n exco get pods -o wide
kubectl -n exco get ingress exco-app
kubectl -n argocd get application exco
printf 'PASS: Argo CD Synced/Healthy; two ready non-root replicas; all routes served through Ingress.\n'
