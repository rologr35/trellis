---
name: init
description: Pone un proyecto bajo trellis. Entrevista a la persona y escribe trellis.config, el CLAUDE.md raíz con el método, los CLAUDE.md por paquete, TESTING.md, .claude/settings.json, los git hooks, el .gitignore y el workflow del CI.
disable-model-invocation: true
---

# init

Corre en el checkout principal del proyecto, en una rama de issue, con el árbol limpio. Las plantillas viven en el plugin: `PLUGIN="$(cd "$(dirname "$(command -v trellis)")/.." && pwd)"`, y `$PLUGIN/templates/`.

## 1. Leer antes de preguntar

Claude deduce del código todo lo que puede y solo pregunta lo que no: el stack y su versión (`pubspec.yaml`, `package.json`, `.tool-versions`), los paquetes del workspace, las ramas (`git branch -a`), el remoto y si es GitHub, los comandos que ya existen (scripts, Makefile, CI), y si ya hay `CLAUDE.md`, `.claude/settings.json` o hooks. Lo existente se conserva y se integra; nada se sobreescribe sin decirlo.

## 2. Entrevista

Una pregunta por tema, con la respuesta deducida como opción por defecto:

1. **Stack y workspace**: `workspace.kind` (flutter, dart, node), los paquetes (`workspace.package`) y las herramientas con su versión mínima (`toolchain.require`).
2. **Ramas**: release, integración, la forma de una rama de issue y las protegidas.
3. **Tracker**: `github` o `none`.
4. **Idioma**: `es` o `en` (`project.locale`).
5. **Comandos**: análisis, formato, pruebas por escalón, instalación de dependencias. Cada escalón: si Claude puede correrlo (`agent`), si corre en cada pull request (`pr`) y qué prueba.
6. **Qué es irreversible**: migraciones, envíos a usuarios, pagos, despliegues. Cada cosa se vuelve una línea de **Nunca** del `CLAUDE.md` raíz y, si tiene ficheros propios, un `[gate]`.
7. **Escáner de secretos**: gitleaks por defecto (`gitleaks protect --staged --redact` en local, `gitleaks git --redact` en CI con `ci =`), otro, o ninguno (el doctor avisa).
8. **Modelos**: `model`, `effortLevel` y `autoCompactWindow` por defecto del proyecto.

## 3. Escribir

1. `trellis.config` desde `$PLUGIN/templates/trellis.config`, con las respuestas. Sin `{{...}}` sin rellenar; lo que no aplica se borra. `trellis config unknown` vacío.
2. `CLAUDE.md` desde `CLAUDE.root.md`: el layout, la anti-duplicación y las convenciones deducidos del código, y **Nunca** con lo irreversible. Si ya existía, su contenido vigente se reparte en esas secciones.
3. El skill `scaffold` para un `CLAUDE.md` por paquete.
4. `TESTING.md` desde su plantilla, una sección por escalón.
5. `.claude/settings.json` desde la plantilla, fusionado con el existente: `allow` y `deny` se unen, lo demás de la persona se conserva. El sha del marketplace es el `gitCommitSha` de `trellis@trellis` en `~/.claude/plugins/installed_plugins.json`, completo (40 caracteres).
6. `.githooks/` desde `$PLUGIN/templates/githooks/`, ejecutables.
7. La línea de `$PLUGIN/templates/gitignore.fragment` en `.gitignore`, si falta.
8. `.github/workflows/trellis.yml` desde `$PLUGIN/templates/workflows/trellis.yml`, con el mismo sha, si el remoto es GitHub.

## 4. Cerrar

En este orden: `trellis setup`, `trellis sync`, `trellis hygiene --freeze`, `trellis hygiene` y `trellis doctor`. Lo que quede en FAIL se arregla o se le dice a la persona con su causa. Después, un commit en la rama (`chore(trellis): init (#n)`), y el resumen: qué se escribió, qué se dedujo y qué se preguntó, qué queda en aviso, y que los `CLAUDE.md` de paquete esperan revisión humana.
