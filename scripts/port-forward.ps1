# Version PowerShell de port-forward.sh (Windows).
# Abre 4 ventanas minimizadas con los port-forward. Para cerrarlas: Get-Process kubectl | Stop-Process
# Si un pod se reinicia, el port-forward correspondiente se cae: vuelve a ejecutar este script.
Get-Process kubectl -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne $null } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Start-Process kubectl -ArgumentList "port-forward -n monitoring svc/monitoring-grafana 3000:80" -WindowStyle Minimized
Start-Process kubectl -ArgumentList "port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090" -WindowStyle Minimized
Start-Process kubectl -ArgumentList "port-forward -n biblioteca svc/catalogo-libros-service 8081:8081" -WindowStyle Minimized
Start-Process kubectl -ArgumentList "port-forward -n biblioteca svc/prestamos-service 8082:8082" -WindowStyle Minimized
Start-Sleep -Seconds 3

Write-Host "Grafana     http://localhost:3000  (admin / Biblioteca2026!)"
Write-Host "Prometheus  http://localhost:9090"
Write-Host "Catalogo    http://localhost:8081"
Write-Host "Prestamos   http://localhost:8082"
