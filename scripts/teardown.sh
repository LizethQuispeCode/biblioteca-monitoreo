#!/usr/bin/env bash
# Elimina todos los recursos del proyecto.
# Uso: bash scripts/teardown.sh             (borra el namespace biblioteca y el stack de monitoreo)
#      bash scripts/teardown.sh --cluster   (ademas borra el cluster de Minikube completo)
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BORRAR_CLUSTER=false
case "${1:-}" in
  "") ;;
  --cluster) BORRAR_CLUSTER=true ;;
  *) echo "Uso: $0 [--cluster]"; exit 1 ;;
esac

paso() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

paso "Cerrando port-forward"
pkill -f "kubectl port-forward" >/dev/null 2>&1 || true

paso "Eliminando recursos del namespace biblioteca"
kubectl delete -f "$RAIZ/k8s/prometheusrule.yaml" --ignore-not-found 2>/dev/null
kubectl delete -f "$RAIZ/k8s/servicemonitors.yaml" --ignore-not-found 2>/dev/null
kubectl delete -f "$RAIZ/k8s/prestamos.yaml" --ignore-not-found
kubectl delete -f "$RAIZ/k8s/catalogo-libros.yaml" --ignore-not-found
kubectl delete namespace biblioteca --ignore-not-found

paso "Eliminando el stack de monitoreo"
kubectl delete configmap biblioteca-dashboard -n monitoring --ignore-not-found
helm uninstall monitoring -n monitoring 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found

if [ "$BORRAR_CLUSTER" = true ]; then
  paso "Eliminando el cluster de Minikube"
  minikube delete
else
  echo
  echo "El cluster de Minikube sigue encendido. Para borrarlo tambien: bash scripts/teardown.sh --cluster"
fi
