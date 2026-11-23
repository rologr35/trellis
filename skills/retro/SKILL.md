---
name: retro
description: Al cerrar un trabajo, propone en el chat la lección que deja y su destino, o "sin cambio" cuando no hay lección. Una persona la aplica.
disable-model-invocation: true
---

# retro

## 1. ¿Hay lección?

Una lección es algo que la próxima sesión haría mal sin ella: un error repetido, una instrucción que faltó o que confundió, un paso caro que se puede evitar. Si no la hay, la respuesta es "sin cambio" y nada más.

## 2. La pieza más barata que la sostenga

En este orden, y la primera que baste:

1. Salida acotada de una herramienta (un flag, un filtro).
2. Un script.
3. Un skill.
4. Un hook, solo con evidencia repetida.
5. Texto corto en un fichero de instrucciones, al final, reemplazando antes que añadiendo.

Un cambio por métrica a la vez, para poder atribuir su efecto.

## 3. Local o del marco

- **Local**: vale para este proyecto. Destino: el `CLAUDE.md` o la rule más cercana al código del que habla, a la altura del concepto.
- **Del marco**: vale para cualquier proyecto (el método, una guarda, la higiene, una plantilla). No se escribe en el proyecto: se cambiaría solo aquí y los demás no la recibirían.

## 4. Proponer

En el chat: la lección en una frase, el incidente que la muestra (qué pasó, dónde consta), su clasificación y el texto o el cambio propuesto con su destino exacto. Claude no lo aplica: una persona decide.

Para una lección del marco, con la aprobación de la persona: buscar antes en el repositorio del plugin (`trellis config get trellis.upstream`) con `gh issue list -R <upstream> --state all --search '<concepto>'`, y si no existe, abrir allí una issue con la lección, el incidente y el texto propuesto (`gh issue create -R <upstream> --body-file`). El proyecto la recibe cuando actualiza el sha fijado del plugin.
