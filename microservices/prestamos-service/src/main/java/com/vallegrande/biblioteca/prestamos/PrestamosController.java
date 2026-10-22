package com.vallegrande.biblioteca.prestamos;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.Exceptions;

import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicLong;

@RestController
public class PrestamosController {

    private static final Logger log = LoggerFactory.getLogger(PrestamosController.class);
    private static final ParameterizedTypeReference<Map<String, Object>> TIPO_MAPA =
            new ParameterizedTypeReference<>() {};

    private final Map<Long, Prestamo> prestamos = new ConcurrentHashMap<>();
    private final AtomicLong secuencia = new AtomicLong(0);
    private final MeterRegistry registry;
    private final WebClient catalogo;
    private final long timeoutMs;

    public PrestamosController(MeterRegistry registry,
                               WebClient.Builder builder,
                               @Value("${catalogo.url}") String catalogoUrl,
                               @Value("${catalogo.timeout-ms}") long timeoutMs) {
        this.registry = registry;
        this.timeoutMs = timeoutMs;
        this.catalogo = builder.baseUrl(catalogoUrl).build();

        // Gauge 1: prestamos activos en este momento
        Gauge.builder("prestamos.activos", prestamos,
                        m -> m.values().stream().filter(p -> "ACTIVO".equals(p.estado())).count())
                .description("Prestamos activos actualmente")
                .register(registry);

        // Gauge 2: timeout configurado hacia el catalogo
        Gauge.builder("prestamos.catalogo.timeout.ms", this, c -> c.timeoutMs)
                .description("Timeout configurado para llamar al catalogo (ms)")
                .register(registry);
    }

    private Map<String, Object> mensaje(String texto) {
        Map<String, Object> cuerpo = new LinkedHashMap<>();
        cuerpo.put("mensaje", texto);
        return cuerpo;
    }

    // 1) Health check propio, sin depender del catalogo
    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP", "servicio", "prestamos-service");
    }

    // 2) Listar prestamos
    @GetMapping("/prestamos")
    public List<Prestamo> listar() {
        return new ArrayList<>(prestamos.values());
    }

    // 3) Obtener un prestamo
    @GetMapping("/prestamos/{id}")
    public ResponseEntity<Prestamo> obtener(@PathVariable Long id) {
        Prestamo prestamo = prestamos.get(id);
        if (prestamo == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(prestamo);
    }

    // 4) Solicitar un prestamo: consulta al Servicio A (catalogo)
    @PostMapping("/prestamos")
    public ResponseEntity<Object> solicitar(@RequestBody SolicitudPrestamo solicitud) {
        Timer.Sample muestra = Timer.start(registry);
        String resultado = "error_catalogo";
        try {
            Map<String, Object> disponibilidad = catalogo.get()
                    .uri("/libros/{id}/disponibilidad", solicitud.libroId())
                    .retrieve()
                    .bodyToMono(TIPO_MAPA)
                    .timeout(Duration.ofMillis(timeoutMs))
                    .block();

            if (disponibilidad == null || !Boolean.TRUE.equals(disponibilidad.get("disponible"))) {
                resultado = "sin_stock";
                return ResponseEntity.status(HttpStatus.CONFLICT)
                        .body(mensaje("El libro no tiene stock disponible"));
            }

            catalogo.post()
                    .uri("/libros/{id}/reservar", solicitud.libroId())
                    .retrieve()
                    .bodyToMono(TIPO_MAPA)
                    .timeout(Duration.ofMillis(timeoutMs))
                    .block();

            long id = secuencia.incrementAndGet();
            Prestamo prestamo = new Prestamo(id, solicitud.libroId(),
                    String.valueOf(disponibilidad.get("titulo")), solicitud.usuario(), "ACTIVO");
            prestamos.put(id, prestamo);
            resultado = "aprobado";
            return ResponseEntity.status(HttpStatus.CREATED).body(prestamo);

        } catch (WebClientResponseException.NotFound e) {
            resultado = "libro_no_existe";
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(mensaje("El libro no existe en el catalogo"));
        } catch (WebClientResponseException.Conflict e) {
            resultado = "sin_stock";
            return ResponseEntity.status(HttpStatus.CONFLICT).body(mensaje("El libro no tiene stock disponible"));
        } catch (RuntimeException e) {
            Throwable causa = Exceptions.unwrap(e);
            String tipo = (causa instanceof TimeoutException) ? "timeout" : "conexion";
            log.error("Fallo la llamada al catalogo ({}): {}", tipo, causa.toString());
            registry.counter("prestamos.catalogo.errores", "tipo", tipo).increment();
            resultado = "error_catalogo";
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(mensaje("El catalogo no responde en este momento. Intenta nuevamente."));
        } finally {
            muestra.stop(Timer.builder("prestamos.catalogo.llamada.duracion")
                    .tag("resultado", resultado)
                    .description("Duracion de las llamadas al catalogo")
                    .publishPercentileHistogram()
                    .register(registry));
            registry.counter("prestamos.solicitudes", "resultado", resultado).increment();
        }
    }

    // 5) Devolver un libro
    @PostMapping("/prestamos/{id}/devolver")
    public ResponseEntity<Object> devolver(@PathVariable Long id) {
        Prestamo prestamo = prestamos.get(id);
        if (prestamo == null) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(mensaje("Prestamo no encontrado"));
        }
        Prestamo devuelto = new Prestamo(prestamo.id(), prestamo.libroId(), prestamo.titulo(),
                prestamo.usuario(), "DEVUELTO");
        prestamos.put(id, devuelto);
        registry.counter("prestamos.devoluciones").increment();
        return ResponseEntity.ok(devuelto);
    }
}