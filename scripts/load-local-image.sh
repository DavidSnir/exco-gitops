#!/bin/sh
# Transitional Part 2 image delivery; app deployment is still exclusively GitOps.
# Build the exact source revision named by the manifest, not a changing worktree.
set -eu

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
image=$(yq -r '.image.repository + ":" + .image.tag' "$repo_dir/k8s/values.yaml")
case "$image" in
  exco-app:sha-*) revision=${image#exco-app:sha-} ;;
  *) printf 'This helper only handles local exco-app:sha-* images; registry images should be pulled normally.\n' >&2; exit 1 ;;
esac
printf '%s\n' "$revision" | grep -Eq '^[0-9a-f]{40}$'
cluster=$(terraform -chdir="$repo_dir/terraform" output -raw cluster_name)

build_dir=$(mktemp -d "${TMPDIR:-/private/tmp/opencode}/exco-image.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
git -C "$repo_dir" archive "$revision" app | tar -x -C "$build_dir"

docker build --provenance=false --build-arg "APP_VERSION=$revision" -t "$image" "$build_dir/app"
kind load docker-image "$image" --name "$cluster"
printf 'Loaded %s into all nodes of kind cluster %s.\n' "$image" "$cluster"
