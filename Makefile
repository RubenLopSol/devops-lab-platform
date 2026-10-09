SHELL := /bin/bash

PROFILE ?= openpanel-rebuild

.PHONY: help cluster-up cluster-stop cluster-down minikube-up minikube-stop minikube-down install-argocd status argocd-password port-forward-argocd render-argocd

.DEFAULT_GOAL := help

help:
	@echo ""
	@echo "OpenPanel rebuild platform"
	@echo "=========================="
	@echo ""
	@echo "Cluster"
	@echo "  make cluster-up          Start Minikube, install ArgoCD, apply bootstrap-app"
	@echo "  make cluster-stop        Stop the Minikube profile without deleting it"
	@echo "  make cluster-down        Delete the Minikube profile"
	@echo "  make minikube-up         Start/select the Minikube profile only"
	@echo "  make minikube-stop       Stop the Minikube profile only"
	@echo "  make minikube-down       Delete the Minikube profile only"
	@echo ""
	@echo "ArgoCD"
	@echo "  make install-argocd      Install ArgoCD and apply bootstrap-app"
	@echo "  make status              Show ArgoCD Applications and deployed image"
	@echo "  make argocd-password     Print the initial admin password"
	@echo "  make port-forward-argocd Forward ArgoCD UI to https://localhost:8081"
	@echo ""
	@echo "Validation"
	@echo "  make render-argocd       Render the dev ArgoCD overlay locally"
	@echo ""
	@echo "Options"
	@echo "  PROFILE=openpanel-rebuild  Minikube profile name"
	@echo ""

cluster-up: minikube-up install-argocd
	@echo ""
	@echo "Cluster bootstrap complete."
	@echo "Run: make status"

cluster-down: minikube-down

cluster-stop: minikube-stop

minikube-up:
	@bash scripts/setup-minikube.sh "$(PROFILE)"

minikube-stop:
	@minikube stop -p "$(PROFILE)"

minikube-down:
	@minikube delete -p "$(PROFILE)"

install-argocd:
	@bash scripts/install-argocd.sh

status:
	@kubectl get applications -n argocd
	@echo ""
	@printf "openpanel-dev project: "
	@kubectl get application openpanel-dev -n argocd -o jsonpath='{.spec.project}'; echo
	@printf "openpanel-dev revision: "
	@kubectl get application openpanel-dev -n argocd -o jsonpath='{.spec.source.targetRevision}'; echo
	@printf "deployed image: "
	@kubectl get deployment openpanel-app -n openpanel -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

argocd-password:
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

port-forward-argocd:
	@kubectl port-forward svc/argocd-server -n argocd 8081:443

render-argocd:
	@kustomize build --enable-helm --load-restrictor=LoadRestrictionsNone k8s/infrastructure/overlays/dev/argocd >/tmp/openpanel-argocd-dev-render.yaml
	@echo "Rendered to /tmp/openpanel-argocd-dev-render.yaml"
