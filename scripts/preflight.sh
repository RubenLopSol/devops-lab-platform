#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

for tool in minikube kubectl docker kustomize helm; do
  require "$tool"
done

docker info >/dev/null 2>&1 || die "Docker daemon is not running"

printf 'OK: required tools are installed and Docker is running\n'
