package com.vallegrande.biblioteca.prestamos;

public record Prestamo(Long id, Long libroId, String titulo, String usuario, String estado) {
}