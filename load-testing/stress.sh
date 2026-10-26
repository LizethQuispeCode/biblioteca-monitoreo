#!/usr/bin/env bash
# Genera trafico hacia los servicios durante las casuisticas.
#
# Uso: load-testing/stress.sh [-s prestamos|catalogo] [-n peticiones] [-i segundos] [-l id_libro] [-u url_base]
#   -s  servicio al que se envia trafico (por defecto: prestamos)
#   -n  cantidad de peticiones (por defecto: 50)
#   -i  pausa entre peticiones en segundos (por defecto: 0.2)
#   -l  id de libro fijo; si no se indica, se elige uno al azar entre 1 y 4
#   -u  URL base; si no se indica, prueba localhost (port-forward) y luego la IP de Minikube
#
# Ejemplos:
#   load-testing/stress.sh -s prestamos -n 40            # pide prestamos de libros al azar
#   load-testing/stress.sh -s catalogo -n 200 -i 0.05    # consulta disponibilidad del catalogo
#   load-testing/stress.sh -s prestamos -n 10 -l 5       # pide siempre el libro 5
set -u

SERVICIO="prestamos"
N=50
INTERVALO="0.2"
LIBRO=""
BASE=""

uso() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts "s:n:i:l:u:h" opcion; do
  case "$opcion" in
    s) SERVICIO="$OPTARG" ;;
    n) N="$OPTARG" ;;
    i) INTERVALO="$OPTARG" ;;
    l) LIBRO="$OPTARG" ;;
    u) BASE="$OPTARG" ;;
    h) uso 0 ;;
    *) uso 1 ;;
  esac
done

case "$SERVICIO" in
  prestamos) PUERTO_LOCAL=8082; NODEPORT=30082 ;;
  catalogo)  PUERTO_LOCAL=8081; NODEPORT=30081 ;;
  *) echo "Servicio invalido: $SERVICIO (usa prestamos o catalogo)"; exit 1 ;;
esac

if [ -z "$BASE" ]; then
  if curl -s -m 2 -o /dev/null "http://localhost:${PUERTO_LOCAL}/health"; then
    BASE="http://localhost:${PUERTO_LOCAL}"
  elif command -v minikube >/dev/null 2>&1 && IP="$(minikube ip 2>/dev/null)" \
       && curl -s -m 2 -o /dev/null "http://${IP}:${NODEPORT}/health"; then
    BASE="http://${IP}:${NODEPORT}"
  else
    echo "No encontre el servicio. Ejecuta 'bash scripts/port-forward.sh' o pasa la URL con -u."
    exit 1
  fi
fi

echo "Servicio: $SERVICIO | URL: $BASE | peticiones: $N | pausa: ${INTERVALO}s"
TMP="$(mktemp)"

for ((i = 1; i <= N; i++)); do
  ID="${LIBRO:-$(( RANDOM % 4 + 1 ))}"
  if [ "$SERVICIO" = "prestamos" ]; then
    CODIGO="$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' \
      -d "{\"libroId\":${ID},\"usuario\":\"estres-${i}\"}" "${BASE}/prestamos")"
  else
    CODIGO="$(curl -s -m 10 -o /dev/null -w '%{http_code}' "${BASE}/libros/${ID}/disponibilidad")"
  fi
  echo "$CODIGO" >> "$TMP"
  printf '%s ' "$CODIGO"
  sleep "$INTERVALO"
done

echo
echo "Resumen (codigo HTTP: cantidad)"
sort "$TMP" | uniq -c | awk '{print "  " $2 ": " $1}'
rm -f "$TMP"
