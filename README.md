# Biblioteca - Microservicios con monitoreo en Kubernetes

Proyecto de la práctica calificada S7 AP7 (Kubernetes con Prometheus y Grafana, Valle Grande).
Autora: Lizeth Yasuri Quispe Suarez.

Dos microservicios en Java para una biblioteca, desplegados en Minikube y monitoreados con Prometheus y Grafana.

| Servicio | Qué hace | Puerto |
|---|---|---|
| `catalogo-libros-service` (A) | Catálogo de libros y control de stock | 8081 |
| `prestamos-service` (B) | Registra préstamos. Antes de aprobar uno, consulta al catálogo con WebClient (con timeout de 2 s) | 8082 |

```
usuario -> prestamos-service --(HTTP + timeout)--> catalogo-libros-service
                |                                          |
                +------------- /metrics -------------------+--> Prometheus --> Grafana
```

## Estructura del repositorio

```
microservices/   código y Dockerfile de los dos servicios (Java 17, Spring Boot 3, Maven)
k8s/             manifiestos de Kubernetes, values.yaml del chart y dashboard de Grafana (JSON)
load-testing/    stress.sh, genera tráfico durante las casuísticas
scripts/         setup.sh, teardown.sh, port-forward.sh / port-forward.ps1, install-linux.sh
docs/            informe.md y capturas
```

## Instalación de las herramientas

Hace falta Docker, Minikube, kubectl y Helm.

**Windows (PowerShell como administrador)**

```powershell
winget install -e --id Docker.DockerDesktop
winget install -e --id Kubernetes.minikube
winget install -e --id Kubernetes.kubectl
winget install -e --id Helm.Helm
winget install -e --id Git.Git
```

Cerrar y abrir PowerShell, abrir Docker Desktop y esperar a que diga "Engine running".

**Linux** (Docker instalado aparte): `bash scripts/install-linux.sh`

**macOS**: `brew install --cask docker` y `brew install minikube kubectl helm`

Verificar:

```
docker info
minikube version
kubectl version --client
helm version
```

## Levantar todo

```
bash scripts/setup.sh
```

Verifica los prerrequisitos, inicia Minikube, habilita metrics-server, instala `kube-prometheus-stack`
con `k8s/monitoring/values.yaml`, construye las imágenes dentro del Docker de Minikube, aplica los
manifiestos y muestra las URLs. En Windows se ejecuta con Git Bash o WSL.

Luego abrir los accesos: `bash scripts/port-forward.sh` (en PowerShell: `scripts\port-forward.ps1`).

## URLs

| Qué | URL | Notas |
|---|---|---|
| Grafana | http://localhost:3000 | usuario `admin`, clave `Biblioteca2026!` |
| Prometheus | http://localhost:9090 | Status > Targets y Alerts |
| Catálogo | http://localhost:8081 | `/health`, `/libros`, `/metrics` |
| Préstamos | http://localhost:8082 | `/health`, `/prestamos`, `/metrics` |

También hay NodePorts: Grafana 30030, Prometheus 30090, Alertmanager 30093, catálogo 30081 y préstamos 30082
(en Linux se entra con `minikube ip`; en Windows con el driver docker conviene usar el port-forward).

## Endpoints

**catalogo-libros-service**: `GET /health`, `GET /metrics`, `GET /libros`, `GET /libros/{id}`, `POST /libros`,
`GET /libros/{id}/disponibilidad`, `POST /libros/{id}/reservar`

**prestamos-service**: `GET /health`, `GET /metrics`, `GET /prestamos`, `GET /prestamos/{id}`,
`POST /prestamos` (cuerpo `{"libroId":1,"usuario":"lizeth"}`), `POST /prestamos/{id}/devolver`

## Métricas propias (Micrometer)

| Servicio | Métrica | Tipo |
|---|---|---|
| catálogo | `catalogo_consultas_total` (tag `tipo`) | Counter |
| catálogo | `catalogo_reservas_total` (tag `resultado`) | Counter |
| catálogo | `catalogo_libros_stock` | Gauge |
| catálogo | `catalogo_delay_artificial_ms` | Gauge |
| catálogo | `catalogo_operacion_duracion_seconds` | Timer |
| préstamos | `prestamos_solicitudes_total` (tag `resultado`) | Counter |
| préstamos | `prestamos_catalogo_errores_total` (tag `tipo`) | Counter |
| préstamos | `prestamos_devoluciones_total` | Counter |
| préstamos | `prestamos_activos` | Gauge |
| préstamos | `prestamos_catalogo_timeout_ms` | Gauge |
| préstamos | `prestamos_catalogo_llamada_duracion_seconds` | Timer |

## Alertas (`k8s/prometheusrule.yaml`)

`CatalogoServiceDown`, `PrestamosServiceDown`, `StockBajoCatalogo`, `PrestamosErroresCatalogo`, `PrestamosRechazadosSinStock`.

## Dashboard

`k8s/dashboards/biblioteca-dashboard.json` tiene 11 paneles. `setup.sh` lo carga en Grafana con un ConfigMap.
Aparece como "Biblioteca - Monitoreo de microservicios".

## Generar tráfico

```
bash load-testing/stress.sh -s prestamos -n 40         # pide préstamos de libros al azar
bash load-testing/stress.sh -s catalogo -n 200 -i 0.05 # consulta el catálogo
bash load-testing/stress.sh -h                         # todas las opciones
```

## Apagar todo

```
bash scripts/teardown.sh             # borra los recursos
bash scripts/teardown.sh --cluster   # además borra el cluster de Minikube
```

## Casuísticas e informe

Están en [docs/informe.md](docs/informe.md): servicio caído (CrashLoopBackOff), servicio lento (timeouts)
y stock agotado.
