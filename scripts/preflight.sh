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

DOCKER_MIN_MAJOR=24

check_docker_version() {
  local version major
  version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)
  major=${version%%.*}

  [[ "$major" =~ ^[0-9]+$ ]] || die "Could not determine Docker server version"
  (( major >= DOCKER_MIN_MAJOR )) || die "Docker ${DOCKER_MIN_MAJOR}+ required (found ${version})"

  printf 'OK: Docker %s\n' "$version"
}

check_docker_version

printf 'OK: required tools are installed and Docker is running\n'
