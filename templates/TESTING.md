# Pruebas

Los escalones de pruebas del proyecto, de lo más barato a lo más caro. `trellis sync` escribe la tabla desde los `[rung]` de `trellis.config`; la columna "Lo corre Claude" con "no" se convierte en un `deny` de `.claude/settings.json`.

<!-- trellis:rungs -->
<!-- /trellis:rungs -->

## Reglas de base

- Nunca contra producción.
- Una prueba no toca red que no le pertenece: los servicios externos se sustituyen en el borde.
- Sin cuarentena de pruebas inestables: una prueba inestable se arregla o se borra con el código que cubre.
- La cobertura es honesta: una prueba que no puede fallar no cuenta.
- Toda prueba nueva se ve fallar antes de verla pasar.
- Las pruebas de un escalón que ningún pull request corre al menos compilan o se analizan en el escalón del pull request, y el cuerpo del pull request dice qué escalón queda esperando.

## Escalones

{{Una sección por escalón, con el mismo nombre que su `[rung]`:}}

### {{nombre del escalón}}

- Qué prueba: {{...}}
- Qué no prueba: {{...}}
- Cuándo va aquí una prueba nueva: {{...}}

## ¿Dónde va una prueba nueva?

{{Un mapa de decisión corto, del tipo: lógica pura sin dependencias, escalón unitario; un widget con su estado, escalón de widgets; un flujo entre pantallas con servicios sustituidos, escalón de integración.}}
