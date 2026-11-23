---
name: scaffold
description: Escribe un CLAUDE.md por paquete del workspace, con sus capas y comandos deducidos del código, para que una persona lo revise.
disable-model-invocation: true
---

# scaffold

Un `CLAUDE.md` por cada `workspace.package` de `trellis.config` que no lo tenga, desde la plantilla `CLAUDE.package.md` del plugin (`$(cd "$(dirname "$(command -v trellis)")/.." && pwd)/templates/`). Un paquete que ya lo tiene no se toca.

## Qué se deduce y de dónde

- **Qué hace el paquete**: su manifiesto (`pubspec.yaml`, `package.json`), su punto de entrada y sus dependencias internas.
- **Capas**: las carpetas de primer nivel bajo su código fuente y la dirección de sus imports. Una capa es una carpeta que importa de otras pero no al revés; si los imports no muestran una dirección, el borrador lo dice en vez de inventarla.
- **Comandos**: los scripts del manifiesto y los del CI que corren en esa carpeta, con lo que hace cada uno. Los que ya están en `trellis check` no se repiten.
- **Reglas**: las rules de `.claude/rules/` cuyos `paths:` cubren ficheros del paquete.

## Límites

- Presente y tercera persona, sin historia ni referencias a issues: la higiene lo comprueba.
- Corto: es el índice del paquete, no su manual. El detalle de un dominio va a una rule con `paths:`.
- Lo que no se pudo deducir queda como pregunta explícita en el borrador.

Al terminar, `trellis sync` (la tabla de orientación los lista) y `trellis hygiene`. El resumen nombra cada fichero escrito y pide su revisión a una persona.
