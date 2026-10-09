#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-openpanel-rebuild}"
K8S_VERSION="${K8S_VERSION:-v1.31.0}"
CPUS="${CPUS:-2}"
MEMORY="${MEMORY:-4096}"
DISK_SIZE="${DISK_SIZE:-30g}"
DRIVER="${DRIVER:-docker}"

info() { printf "\n==> %s\n" "$*"; }
ok() { printf "OK: %s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

require minikube
require kubectl
require docker

info "Starting/selecting Minikube profile: ${PROFILE}"
if minikube status -p "${PROFILE}" >/dev/null 2>&1; then
  ok "Minikube profile already running"
else
  minikube start \
    -p "${PROFILE}" \
    --kubernetes-version="${K8S_VERSION}" \
    --driver="${DRIVER}" \
    --cpus="${CPUS}" \
    --memory="${MEMORY}" \
    --disk-size="${DISK_SIZE}"
fi

kubectl config use-context "${PROFILE}" >/dev/null

info "Waiting for node readiness"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

ok "Cluster is ready"
kubectl get nodes -o wide
