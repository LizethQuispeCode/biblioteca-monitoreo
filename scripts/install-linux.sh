#!/usr/bin/env bash
# Instala kubectl, minikube y helm en Linux (amd64 o arm64) si no estan instalados.
# Docker debe estar instalado aparte. Uso: bash scripts/install-linux.sh
set -euo pipefail

ARQ="$(uname -m)"
case "$ARQ" in
  x86_64)  ARQ=amd64 ;;
  aarch64|arm64) ARQ=arm64 ;;
  *) echo "Arquitectura no soportada: $ARQ"; exit 1 ;;
esac

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Instalando kubectl..."
  VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${VERSION}/bin/linux/${ARQ}/kubectl"
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

if ! command -v minikube >/dev/null 2>&1; then
  echo "Instalando minikube..."
  curl -fsSLo /tmp/minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${ARQ}"
  sudo install -m 0755 /tmp/minikube /usr/local/bin/minikube
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "Instalando helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo
kubectl version --client
minikube version
helm version
