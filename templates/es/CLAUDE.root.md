# {{project.name}}

{{Una o dos frases: qué es el proyecto y para quién.}}

<!-- trellis:method -->
<!-- /trellis:method -->

## Orientación

Ficheros de instrucciones del proyecto y cuándo carga cada uno. `trellis sync` escribe la tabla.

<!-- trellis:orientation -->
<!-- /trellis:orientation -->

## Comandos

<!-- trellis:commands -->
<!-- /trellis:commands -->

## Gates

<!-- trellis:gates -->
<!-- /trellis:gates -->

## Layout

{{Dónde vive cada cosa: un renglón por carpeta de primer nivel o paquete, con lo que contiene y lo que no. Es la referencia para decidir el hogar de un fichero nuevo.}}

## Anti-duplicación en este proyecto

{{Las definiciones canónicas que más se duplican aquí (por ejemplo: formato de fechas, cliente HTTP, tema visual) y el fichero donde vive cada una.}}

## Convenciones

{{Las convenciones que el lint no impone: nombres, estructura de un módulo, manejo de errores, textos visibles.}}

## Nunca

- Nunca commitear en la rama de release ni en la de integración.
- Nunca push sin refspec explícito.
- Nunca correr un escalón de pruebas que `TESTING.md` marca como no ejecutable por Claude.
{{Lo irreversible de este proyecto, una línea cada cosa: migraciones en producción, envíos a usuarios, pagos.}}

## Antes de dar por terminado

- [ ] `trellis check` en verde.
- [ ] `trellis hygiene` en verde si el cambio toca instrucciones.
- [ ] Pruebas nuevas según el mapa de `TESTING.md`, vistas fallar antes de pasar.
- [ ] Commit en la rama de la issue, push con refspec explícito, pull request con **Resumen** y **Verificación**.
