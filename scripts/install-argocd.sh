#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NAMESPACE="argocd"
BASE_INSTALL="k8s/infrastructure/base/argocd/install"
ARGOCD_OVERLAY="k8s/infrastructure/overlays/dev/argocd"
BOOTSTRAP_APP="${ARGOCD_OVERLAY}/bootstrap-app.yaml"

info() { printf "\n==> %s\n" "$*"; }
ok() { printf "OK: %s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

require kubectl
require kustomize

[[ -d "${BASE_INSTALL}" ]] || die "Missing base install path: ${BASE_INSTALL}"
[[ -d "${ARGOCD_OVERLAY}" ]] || die "Missing ArgoCD overlay path: ${ARGOCD_OVERLAY}"
[[ -f "${BOOTSTRAP_APP}" ]] || die "Missing bootstrap Application: ${BOOTSTRAP_APP}"

info "Pass 1: installing ArgoCD chart from base"
kustomize build --enable-helm "${BASE_INSTALL}" | kubectl apply -f -
ok "ArgoCD base install applied"

info "Waiting for ArgoCD CRDs"
for crd in applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io; do
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=120s
done
ok "ArgoCD CRDs established"

info "Waiting for ArgoCD workloads"
kubectl rollout status statefulset/argocd-application-controller -n "${ARGOCD_NAMESPACE}" --timeout=5m
kubectl rollout status deployment/argocd-repo-server -n "${ARGOCD_NAMESPACE}" --timeout=5m
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=5m
ok "ArgoCD workloads are ready"

info "Pass 2: applying full dev ArgoCD overlay"
kustomize build --enable-helm --load-restrictor=LoadRestrictionsNone "${ARGOCD_OVERLAY}" | kubectl apply -f -
ok "ArgoCD overlay applied"

info "Applying bootstrap Application"
kubectl apply -f "${BOOTSTRAP_APP}"
ok "bootstrap-app applied"

info "Refreshing bootstrap-app"
kubectl annotate application bootstrap-app -n "${ARGOCD_NAMESPACE}" argocd.argoproj.io/refresh=hard --overwrite >/dev/null || true

info "Current ArgoCD Applications"
kubectl get applications -n "${ARGOCD_NAMESPACE}" || true

cat <<'MSG'

Next checks:
  kubectl get applications -n argocd
  make status
  make port-forward-argocd

MSG
