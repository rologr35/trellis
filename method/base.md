## Método de trabajo

Este bloque lo escribe `trellis sync` desde el plugin; se cambia en el plugin, no aquí. Describe cómo trabaja Claude en este proyecto, en cada turno.

### Antes de ejecutar

- Claude estudia el flujo completo antes de tocarlo: quién llama, qué lee, qué escribe, qué lo prueba.
- Los huecos que se cierran leyendo (código, config, historial, logs) se cierran antes de proponer. "No establecido" se dice solo de lo que no se puede comprobar, y se dice.
- Claude propone antes de ejecutar y espera la aprobación. Considera antes una alternativa externa (una librería, una herramienta, un servicio) que construir.
- Lo simple gana a lo ingenioso. Sin abstracción hasta dos usos reales. Sin feature flags de "despliegue seguro": lo que espera una fecha sale activable por configuración.
- La pregunta del trinquete: ¿este cambio afloja algo que hoy se impide? Si sí, se dice antes de hacerlo (ver Trinquetes).
- Antes de dar algo por hecho corren el typecheck y el lint reales del proyecto (`trellis check`), no una lectura del diff.
- El informe es honesto: lo que falló se dice con su salida, lo que no se hizo se dice, lo verificado se afirma sin rodeos.

### Entregar

- Claude entrega la solución terminada y escala solo lo que necesita a una persona: una decisión, un acceso, algo irreversible.
- Una pregunta de la persona a mitad de tarea es una pregunta, no una orden de cambiar de rumbo.
- Cuando Claude ve cómo hacer su propio trabajo más eficiente, lo propone con datos: qué cuesta hoy y qué costaría.

### Anti-duplicación

- Se busca primero por ficheros y después por líneas, antes de escribir algo que quizá exista.
- Cada valor derivado tiene una definición canónica. Una segunda copia es un defecto aunque hoy coincida.
- Cambiar el significado de una métrica barre todos sus consumidores en el mismo cambio.
- El hogar de un fichero nuevo se decide explícitamente, según el layout de este `CLAUDE.md`.
- Lo reemplazado se borra en el mismo cambio que lo reemplaza.
- Las métricas son honestas: miden lo que dicen medir.

### Git

- Claude nunca commitea en la rama de release ni en la de integración: cada issue se trabaja en su worktree (`trellis worktree add <n> <slug>`).
- Un push lleva siempre refspec explícito (`git push origin <rama>`): la guarda juzga un push desnudo por la rama del checkout.
- Nunca `amend`, `reset` ni `force-push` sin la aprobación de esa acción concreta. "Procede" o "sigue" no aprueban esas acciones.
- Nunca se descartan cambios del árbol de trabajo para ordenar. Un cambio sin commit no es almacenamiento: el trabajo que sobrevive a la sesión se commitea en una rama en el mismo turno.

### Trinquetes

- Un trinquete impide que algo limpiado vuelva a crecer: supresiones, pruebas, reglas de lint, límites de tamaño, listas de excepciones.
- Antes de aflojar uno, Claude objeta con datos: qué retrocede, cuánto cuesta y qué alternativa no retrocede. Después espera a la persona. Con su confirmación, `git config branch.<rama>.ratchet-loosened true`, y el pull request lleva la sección **Retroceso**.
- Una guarda nueva se mide contra el historial ya mezclado mientras se planifica, no al ejecutarla: cuántos casos del historial habría parado, y cuántos sin razón.
- Un escalón de pruebas que se apaga lleva fecha de vuelta (`offUntil`), y encenderlo cuesta una corrida completa de puesta al día.

### Worktrees

- `EnterWorktree` actúa solo cuando este texto lo nombra para la tarea: después de `trellis worktree add`, con la ruta que imprime.
- Se sale con `ExitWorktree` y `keep`, nunca con `remove`: `trellis worktree prune` decide qué se borra.
- Dentro de una sesión de worktree, Claude Code rechaza Bash con git en forma compleja (heredocs, `$(...)`, bucles, incluso la palabra en una ruta). El texto largo va por Write y Bash corre líneas simples.

### Conflictos en ficheros de instrucciones

Un conflicto en un `CLAUDE.md`, una rule o un skill se resuelve desde la versión de la propia rama más su propio cambio, nunca reconstruyendo el fichero desde la rama de integración.

### Memoria

- La memoria guarda preferencias y punteros, no estado. El estado (migraciones pendientes, código sin commit, el estado de una plantilla) se relee de su fuente al usarlo.
- Lo que hizo otra sesión vive en su transcript (`~/.claude/projects/**/*.jsonl`), no en git. Una hipótesis que una consulta barata puede comprobar se comprueba antes de cargarla.

### Coste

- Más uso de Claude nunca es gratis. Una propuesta que añade corridas, revisiones o subagentes dice su peso en el cupo.
- La palanca grande es la salida corta de las herramientas (leer rangos, no ficheros enteros; filtrar la salida), no bajar el esfuerzo.

### Planes

- Antes de proponer un plan, el agent `plan-reviewer` lo comprueba en contexto limpio, y su veredicto va con la propuesta.
- Ningún plan vive en una carpeta ignorada por git. El contexto de negocio va a `docs/`.
- Lo que se aprende del código va al `CLAUDE.md` o la rule más cercana a ese código, a la altura del concepto.

### Entregas

- Todo pull request es un incremento liberable.
- Lo que espera una fecha sale activable por configuración.
- Un backfill nunca deja una vista vacía entre el despliegue y un script.
- Una prueba que el plan nombra se escribe aunque no se pueda correr en local, y el pull request dice qué escalón queda esperando.
- Una barrera de calidad llega a la rama de release o no existe. El lint va dentro de la barrera: sacarlo por deriva acumulada es irreversible en la práctica.

### Subagentes

- Un subagente o una rutina recibe las reglas críticas en su prompt, sin pedirle leer lo que el arnés ya le carga.
- Su informe lleva un tope de longitud y es una afirmación que se verifica, no un hecho.
- Comparte el sistema de ficheros: escribe con `mktemp`, y el padre usa nombres únicos.
- Una búsqueda lleva un modelo barato. Trabajos hermanos van en pestañas, no en subagentes.
