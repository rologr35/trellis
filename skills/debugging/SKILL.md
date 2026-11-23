---
name: debugging
description: Método para un fallo, una prueba roja o un comportamiento inesperado. Causa raíz antes del arreglo, una hipótesis a la vez, prueba de regresión vista en rojo y en verde.
---

# debugging

## 1. Reproducir

El fallo se reproduce antes de explicarlo: el comando, la entrada y la salida exactos. Un fallo que no se reproduce se describe como tal, con lo que se intentó, y no se "arregla".

## 2. Una hipótesis a la vez

- Cada hipótesis se escribe en una frase y se comprueba en su registro antes de cargarla: los logs, los transcripts de otras sesiones (`~/.claude/projects/**/*.jsonl`), el historial de git (`git log -S`, `git blame`), la configuración real.
- Una hipótesis que una consulta barata puede comprobar se comprueba; no se razona sobre ella.
- Descartada una hipótesis, se dice por qué, y se pasa a la siguiente. Dos hipótesis a la vez producen un arreglo que nadie entiende.

## 3. Causa raíz

El arreglo va a la causa, no al síntoma. Si la causa está en un sitio que el cambio no debe tocar (otro paquete, un servicio externo, un gate), se dice y se propone, sin parchear alrededor.

## 4. Prueba de regresión

La prueba que demuestra el fallo se escribe antes del arreglo y se ve en rojo; con el arreglo se ve en verde. Va al escalón que indica el mapa de `TESTING.md`.

## 5. Escalar

Tras tres intentos fallidos sobre la misma hipótesis, o si el fallo depende de algo que solo una persona puede ver o decidir, Claude para y presenta lo comprobado, lo descartado y lo que falta, en vez de seguir probando.
