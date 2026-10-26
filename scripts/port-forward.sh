#!/usr/bin/env bash
# Abre en segundo plano los port-forward hacia Grafana, Prometheus y los dos microservicios.
# Uso: bash scripts/port-forward.sh        (para cerrarlos: pkill -f "kubectl port-forward")
set -u

pkill -f "kubectl port-forward" >/dev/null 2>&1 || true
sleep 1
LOG=/tmp/port-forward-logs
mkdir -p "$LOG"

nohup kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 >"$LOG/grafana.log" 2>&1 &
nohup kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 >"$LOG/prometheus.log" 2>&1 &
nohup kubectl port-forward -n biblioteca svc/catalogo-libros-service 8081:8081 >"$LOG/catalogo.log" 2>&1 &
nohup kubectl port-forward -n biblioteca svc/prestamos-service 8082:8082 >"$LOG/prestamos.log" 2>&1 &
sleep 3

echo "Grafana     http://localhost:3000  (admin / Biblioteca2026!)"
echo "Prometheus  http://localhost:9090"
echo "Catalogo    http://localhost:8081"
echo "Prestamos   http://localhost:8082"
echo "Logs en $LOG"
