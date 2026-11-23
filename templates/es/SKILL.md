---
name: {{name}}
description: {{Cuándo se usa, en una frase que Claude pueda reconocer en una petición.}}
disable-model-invocation: true
---

# {{name}}

`disable-model-invocation: true` hace que el skill corra solo cuando una persona lo invoca (`/{{name}}`). Se quita únicamente si Claude debe poder decidir usarlo solo; un skill que escribe ficheros, abre issues o cambia la configuración lo conserva.

## Pasos

1. {{...}}
