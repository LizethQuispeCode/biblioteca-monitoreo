package com.vallegrande.biblioteca.catalogo;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Supplier;

@RestController
public class CatalogoController {

    private final Map<Long, Libro> libros = new ConcurrentHashMap<>();
    private final AtomicLong secuencia = new AtomicLong(0);
    private final MeterRegistry registry;
    private final long delayMs;

    public CatalogoController(MeterRegistry registry,
                              @Value("${catalogo.delay-ms:0}") long delayMs) {
        this.registry = registry;
        this.delayMs = delayMs;

        agregar("Cien anos de soledad", "Gabriel Garcia Marquez", 3);
        agregar("El tunel", "Ernesto Sabato", 2);
        agregar("Los rios profundos", "Jose Maria Arguedas", 1);
        agregar("La ciudad y los perros", "Mario Vargas Llosa", 4);

        // Gauge 1: stock total de libros en el catalogo
        Gauge.builder("catalogo.libros.stock.total", libros,
                        m -> m.values().stream().mapToInt(Libro::stock).sum())
                .description("Stock total de libros disponibles en el catalogo")
                .register(registry);

        // Gauge 2: delay artificial configurado (visible en Grafana)
        Gauge.builder("catalogo.delay.artificial.ms", this, c -> c.delayMs)
                .description("Delay artificial configurado en milisegundos")
                .register(registry);
    }

    private Libro agregar(String titulo, String autor, int stock) {
        long id = secuencia.incrementAndGet();
        Libro libro = new Libro(id, titulo, autor, stock);
        libros.put(id, libro);
        return libro;
    }

    private void aplicarDelay() {
        if (delayMs > 0) {
            try {
                Thread.sleep(delayMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    // Timer: mide la duracion de cada operacion del catalogo
    private <T> T medir(String operacion, Supplier<T> accion) {
        return Timer.builder("catalogo.operacion.duracion")
                .tag("operacion", operacion)
                .description("Duracion de las operaciones del catalogo")
                .publishPercentileHistogram()
                .register(registry)
                .record(accion);
    }

    // Counter: consultas por tipo
    private void contarConsulta(String tipo) {
        registry.counter("catalogo.consultas", "tipo", tipo).increment();
    }

    // 1) Health check propio, sin depender de otros servicios
    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP", "servicio", "catalogo-libros-service");
    }

    // 2) Listar libros
    @GetMapping("/libros")
    public List<Libro> listar() {
        return medir("listar", () -> {
            contarConsulta("listar");
            return new ArrayList<>(libros.values());
        });
    }

    // 3) Obtener un libro
    @GetMapping("/libros/{id}")
    public ResponseEntity<Libro> obtener(@PathVariable Long id) {
        return medir("obtener", () -> {
            contarConsulta("obtener");
            Libro libro = libros.get(id);
            if (libro == null) {
                return ResponseEntity.notFound().build();
            }
            return ResponseEntity.ok(libro);
        });
    }

    // 4) Registrar un libro nuevo
    @PostMapping("/libros")
    public ResponseEntity<Libro> crear(@RequestBody Libro nuevo) {
        return medir("crear", () -> {
            contarConsulta("crear");
            Libro creado = agregar(nuevo.titulo(), nuevo.autor(), nuevo.stock());
            return ResponseEntity.status(HttpStatus.CREATED).body(creado);
        });
    }

    // 5) Disponibilidad (lo consulta el Servicio B)
    @GetMapping("/libros/{id}/disponibilidad")
    public ResponseEntity<Map<String, Object>> disponibilidad(@PathVariable Long id) {
        aplicarDelay();
        return medir("disponibilidad", () -> {
            contarConsulta("disponibilidad");
            Libro libro = libros.get(id);
            if (libro == null) {
                return ResponseEntity.notFound().build();
            }
            Map<String, Object> respuesta = new LinkedHashMap<>();
            respuesta.put("id", libro.id());
            respuesta.put("titulo", libro.titulo());
            respuesta.put("stock", libro.stock());
            respuesta.put("disponible", libro.stock() > 0);
            return ResponseEntity.ok(respuesta);
        });
    }

    // 6) Reservar una copia (descuenta stock)
    @PostMapping("/libros/{id}/reservar")
    public synchronized ResponseEntity<Map<String, Object>> reservar(@PathVariable Long id) {
        aplicarDelay();
        return medir("reservar", () -> {
            Libro libro = libros.get(id);
            if (libro == null) {
                return ResponseEntity.notFound().build();
            }
            Map<String, Object> respuesta = new LinkedHashMap<>();
            if (libro.stock() <= 0) {
                registry.counter("catalogo.reservas", "resultado", "sin_stock").increment();
                respuesta.put("reservado", false);
                respuesta.put("mensaje", "No hay stock disponible");
                return ResponseEntity.status(HttpStatus.CONFLICT).body(respuesta);
            }
            libros.put(id, new Libro(libro.id(), libro.titulo(), libro.autor(), libro.stock() - 1));
            registry.counter("catalogo.reservas", "resultado", "ok").increment();
            respuesta.put("reservado", true);
            respuesta.put("stockRestante", libro.stock() - 1);
            return ResponseEntity.ok(respuesta);
        });
    }
}