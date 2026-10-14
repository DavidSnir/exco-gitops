#!/bin/sh
# Read-only acceptance checks. Run after apply; no kubectl apply or Helm install.
set -eu

terraform_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
export KUBECONFIG
KUBECONFIG=$(terraform -chdir="$terraform_dir" output -raw kubeconfig_path)
app_url=$(terraform -chdir="$terraform_dir" output -raw app_url)

kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes -o json | jq -e '
  (.items | length) == 3 and
  ([.items[] | select(.metadata.labels | has("node-role.kubernetes.io/control-plane"))] | length) == 1
' >/dev/null
kubectl get nodes -o wide

kubectl -n argocd wait --for=condition=Available deployment --all --timeout=180s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=180s
kubectl -n traefik rollout status deployment/traefik --timeout=180s

helm list -A -o json | jq -e '
  [.[] | select((.name == "argocd" or .name == "traefik") and .status == "deployed")] | length == 2
' >/dev/null
kubectl -n traefik get service traefik -o json | jq -e '
  .spec.type == "NodePort" and
  .spec.externalTrafficPolicy == "Cluster" and
  any(.spec.ports[]; .port == 80 and .nodePort == 30080)
' >/dev/null
kubectl get ingressclass traefik

# Before Part 2, 404 proves that traffic reaches the controller.
# Once the app is deployed: EXPECTED_HTTP_STATUS=200 sh terraform/check.sh
expected_status=${EXPECTED_HTTP_STATUS:-404}
actual_status=$(curl --max-time 10 -sS -o /dev/null -w '%{http_code}' "$app_url")
if [ "$actual_status" != "$expected_status" ]; then
  printf 'FAIL: %s returned HTTP %s, expected %s\n' "$app_url" "$actual_status" "$expected_status" >&2
  exit 1
fi

printf 'PASS: three Ready nodes, both releases deployed, ingress reachable (HTTP %s).\n' "$actual_status"
