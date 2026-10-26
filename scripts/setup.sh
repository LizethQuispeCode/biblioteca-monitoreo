#!/usr/bin/env bash
# Levanta todo el sistema desde cero:
#   verifica prerrequisitos -> inicia Minikube -> instala Prometheus/Grafana (Helm)
#   -> construye las imagenes -> aplica los manifiestos -> muestra las URLs.
#
# Uso:   bash scripts/setup.sh
# Variables opcionales: MINIKUBE_CPUS, MINIKUBE_MEMORY (en MB)
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS_APP="biblioteca"
NS_MON="monitoring"
GRAFANA_PASS="Biblioteca2026!"   # debe coincidir con k8s/monitoring/values.yaml

paso()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fallo() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. Prerrequisitos
paso "1/8 Verificando prerrequisitos"
for cmd in docker minikube kubectl helm curl; do
  command -v "$cmd" >/dev/null 2>&1 || fallo "Falta '$cmd'. Instalalo siguiendo la seccion Instalacion del README y vuelve a ejecutar."
done
docker info >/dev/null 2>&1 || fallo "Docker no esta corriendo. Abre Docker Desktop (o inicia el servicio de Docker) y vuelve a ejecutar."

DOCKER_CPUS="$(docker info --format '{{.NCPU}}')"
DOCKER_MB=$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 ))
CPUS="${MINIKUBE_CPUS:-$(( DOCKER_CPUS > 4 ? 4 : DOCKER_CPUS ))}"
MEM="${MINIKUBE_MEMORY:-$(( DOCKER_MB * 70 / 100 ))}"
(( MEM > 6144 )) && MEM=6144
(( CPUS >= 2 )) || fallo "Docker solo tiene $DOCKER_CPUS CPU. Minikube necesita al menos 2."
(( MEM >= 3000 )) || fallo "Docker solo tiene ${DOCKER_MB} MB de memoria. Se necesitan al menos 4 GB (Docker Desktop > Settings > Resources)."
echo "Docker: ${DOCKER_CPUS} CPU, ${DOCKER_MB} MB  ->  Minikube usara ${CPUS} CPU y ${MEM} MB"

# ---------------------------------------------------------------- 2. Cluster
paso "2/8 Iniciando Minikube"
if minikube status >/dev/null 2>&1; then
  echo "Minikube ya esta corriendo."
else
  minikube start --driver=docker --cpus="$CPUS" --memory="$MEM"
fi
kubectl config use-context minikube >/dev/null
kubectl wait --for=condition=Ready node/minikube --timeout=180s
minikube addons enable metrics-server

# ---------------------------------------------------------------- 3. Monitoreo
paso "3/8 Instalando kube-prometheus-stack (puede tardar varios minutos)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
kubectl create namespace "$NS_MON" --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n "$NS_MON" -f "$RAIZ/k8s/monitoring/values.yaml" --wait --timeout 15m

# ---------------------------------------------------------------- 4. Dashboard
paso "4/8 Cargando el dashboard de Grafana"
kubectl create configmap biblioteca-dashboard -n "$NS_MON" \
  --from-file=biblioteca-dashboard.json="$RAIZ/k8s/dashboards/biblioteca-dashboard.json" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap biblioteca-dashboard -n "$NS_MON" grafana_dashboard=1 --overwrite

# ---------------------------------------------------------------- 5. Imagenes
paso "5/8 Construyendo las imagenes dentro del Docker de Minikube"
eval "$(minikube -p minikube docker-env --shell bash)"
docker build -t catalogo-libros-service:1.0 "$RAIZ/microservices/catalogo-libros-service"
docker build -t prestamos-service:1.0 "$RAIZ/microservices/prestamos-service"
eval "$(minikube -p minikube docker-env --shell bash --unset)"

# ---------------------------------------------------------------- 6. Manifiestos
paso "6/8 Aplicando los manifiestos de Kubernetes"
kubectl apply -f "$RAIZ/k8s/00-namespace.yaml"
kubectl apply -f "$RAIZ/k8s/catalogo-libros.yaml" -f "$RAIZ/k8s/prestamos.yaml"
kubectl apply -f "$RAIZ/k8s/servicemonitors.yaml" -f "$RAIZ/k8s/prometheusrule.yaml"

paso "7/8 Esperando a que los pods esten listos"
kubectl rollout status deployment/catalogo-libros-service -n "$NS_APP" --timeout=300s
kubectl rollout status deployment/prestamos-service -n "$NS_APP" --timeout=300s
kubectl get pods -n "$NS_APP"

# ---------------------------------------------------------------- 8. URLs
paso "8/8 Listo. Accesos"
IP="$(minikube ip 2>/dev/null || echo '<minikube-ip>')"
cat <<TXT

Abre los accesos con:  bash scripts/port-forward.sh

  Grafana      http://localhost:3000   (usuario: admin / clave: ${GRAFANA_PASS})
  Prometheus   http://localhost:9090   (Status > Targets, Alerts)
  Catalogo     http://localhost:8081   (/health, /libros, /metrics)
  Prestamos    http://localhost:8082   (/health, /prestamos, /metrics)

NodePorts (en Linux se puede entrar directo a la IP de Minikube: ${IP}):
  Grafana ${IP}:30030 | Prometheus ${IP}:30090 | Alertmanager ${IP}:30093
  Catalogo ${IP}:30081 | Prestamos ${IP}:30082

Generar trafico:   bash load-testing/stress.sh -s prestamos -n 30
Apagar todo:       bash scripts/teardown.sh   (agrega --cluster para borrar Minikube)
TXT
