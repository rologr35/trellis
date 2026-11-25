## Método de trabajo

Este bloque lo escribe `trellis sync` desde trellis (`.trellis/`); se cambia en trellis, no aquí. Describe cómo trabaja Claude en este proyecto, en cada turno.

### Antes de ejecutar

- Claude estudia el flujo completo antes de tocarlo: quién llama, qué lee, qué escribe, qué lo prueba. <!-- p:study-flow -->
- Los huecos que se cierran leyendo (código, config, historial, logs) se cierran antes de proponer. "No establecido" se dice solo de lo que no se puede comprobar, y se dice. <!-- p:close-gaps -->
- Claude propone antes de ejecutar y espera la aprobación. Considera antes una alternativa externa (una librería, una herramienta, un servicio) que construir. <!-- p:propose-first -->
- Lo simple gana a lo ingenioso. Sin abstracción hasta dos usos reales. Sin feature flags de "despliegue seguro": lo que espera una fecha sale activable por configuración. <!-- p:simple -->
- La pregunta del trinquete: ¿este cambio afloja algo que hoy se impide? Si sí, se dice antes de hacerlo (ver Trinquetes). <!-- p:ratchet-question -->
- Antes de dar algo por hecho corren el typecheck y el lint reales del proyecto (`trellis check`), no una lectura del diff. <!-- p:real-check -->
- El informe es honesto: lo que falló se dice con su salida, lo que no se hizo se dice, lo verificado se afirma sin rodeos. <!-- p:honest-report -->

### Entregar

- Claude entrega la solución terminada y escala solo lo que necesita a una persona: una decisión, un acceso, algo irreversible. <!-- p:finished-solution -->
- Una pregunta de la persona a mitad de tarea es una pregunta, no una orden de cambiar de rumbo. <!-- p:question-not-order -->
- Cuando Claude ve cómo hacer su propio trabajo más eficiente, lo propone con datos: qué cuesta hoy y qué costaría. <!-- p:propose-efficiency -->

### Anti-duplicación

- Se busca primero por ficheros y después por líneas, antes de escribir algo que quizá exista. <!-- p:search-first -->
- Cada valor derivado tiene una definición canónica. Una segunda copia es un defecto aunque hoy coincida. <!-- p:canonical -->
- Cambiar el significado de una métrica barre todos sus consumidores en el mismo cambio. <!-- p:metric-sweep -->
- El hogar de un fichero nuevo se decide explícitamente, según el layout de este `CLAUDE.md`. <!-- p:file-home -->
- Lo reemplazado se borra en el mismo cambio que lo reemplaza. <!-- p:delete-replaced -->
- Las métricas son honestas: miden lo que dicen medir. <!-- p:honest-metrics -->

### Git

- Claude nunca commitea en la rama de release ni en la de integración: cada issue se trabaja en su worktree (`trellis worktree add <n> <slug>`). <!-- p:no-commit-protected -->
- Un push lleva siempre refspec explícito (`git push origin <rama>`): la guarda juzga un push desnudo por la rama del checkout. <!-- p:explicit-refspec -->
- Nunca `amend`, `reset` ni `force-push` sin la aprobación de esa acción concreta. "Procede" o "sigue" no aprueban esas acciones. <!-- p:no-rewrite -->
- Nunca se descartan cambios del árbol de trabajo para ordenar. Un cambio sin commit no es almacenamiento: el trabajo que sobrevive a la sesión se commitea en una rama en el mismo turno. <!-- p:keep-worktree-changes -->

### Trinquetes

- Un trinquete impide que algo limpiado vuelva a crecer: supresiones, pruebas, reglas de lint, límites de tamaño, listas de excepciones. <!-- p:ratchet-definition -->
- Antes de aflojar uno, Claude objeta con datos: qué retrocede, cuánto cuesta y qué alternativa no retrocede. Después espera a la persona. Con su confirmación, `git config branch.<rama>.ratchet-loosened true`, y el pull request lleva la sección **Retroceso**. <!-- p:ratchet-objection -->
- Una guarda nueva se mide contra el historial ya mezclado mientras se planifica, no al ejecutarla: cuántos casos del historial habría parado, y cuántos sin razón. <!-- p:guard-history -->
- Un escalón de pruebas que se apaga lleva fecha de vuelta (`offUntil`), y encenderlo cuesta una corrida completa de puesta al día. <!-- p:rung-off -->

### Worktrees

- `EnterWorktree` actúa solo cuando este texto lo nombra para la tarea: después de `trellis worktree add`, con la ruta que imprime. <!-- p:enter-worktree -->
- Se sale con `ExitWorktree` y `keep`, nunca con `remove`: `trellis worktree prune` decide qué se borra. <!-- p:exit-keep -->
- Dentro de una sesión de worktree, Claude Code rechaza Bash con git en forma compleja (heredocs, `$(...)`, bucles, incluso la palabra en una ruta). El texto largo va por Write y Bash corre líneas simples. <!-- p:worktree-bash -->

### Conflictos en ficheros de instrucciones

Un conflicto en un `CLAUDE.md`, una rule o un skill se resuelve desde la versión de la propia rama más su propio cambio, nunca reconstruyendo el fichero desde la rama de integración. <!-- p:instruction-conflicts -->

### Memoria

- La memoria guarda preferencias y punteros, no estado. El estado (migraciones pendientes, código sin commit, el estado de una plantilla) se relee de su fuente al usarlo. <!-- p:memory-pointers -->
- Lo que hizo otra sesión vive en su transcript (`~/.claude/projects/**/*.jsonl`), no en git. Una hipótesis que una consulta barata puede comprobar se comprueba antes de cargarla. <!-- p:other-sessions -->

### Coste

- Más uso de Claude nunca es gratis. Una propuesta que añade corridas, revisiones o subagentes dice su peso en el cupo. <!-- p:cost-weight -->
- La palanca grande es la salida corta de las herramientas (leer rangos, no ficheros enteros; filtrar la salida), no bajar el esfuerzo. <!-- p:short-output -->

### Planes

- Antes de proponer un plan, el agent `trellis-plan-reviewer` lo comprueba en contexto limpio, con el pedido al que responde: su veredicto va con la propuesta, y cada uno de sus puntos como corregido o rechazado, con el motivo. <!-- p:plan-reviewer -->
- Ningún plan vive en una carpeta ignorada por git. El contexto de negocio va a `docs/`. <!-- p:plan-tracked -->
- Lo que se aprende del código va al `CLAUDE.md` o la rule más cercana a ese código, a la altura del concepto. <!-- p:learned-near-code -->

<!-- cycle -->
### Ciclo

- El plan aprobado vive en la issue, escrito desde el molde (`.trellis/templates/es/issue.md`) y creada con `trellis issue create --title <t> --body-file <fichero>`, que lo comprueba y le pone la etiqueta de su complejidad. <!-- p:plan-in-issue -->
- El cuerpo de una issue no se edita. Un cambio del plan es un comentario encabezado `## Enmienda (<fecha>)`, con las secciones que sustituye, enteras, como títulos `###`. <!-- p:issue-amendment -->
- Una issue se trabaja con `/trellis-work <n>`: al tomarla `trellis issue check <n>` pasa (con `--print`, el plan vigente), y antes de escribir el cuerpo se trae la rama de integración: lo que se afirma de ella se comprueba ahí. <!-- p:work-skill -->
- Una issue sin plan (un síntoma, una lección) es legítima. Se crea con `gh issue create` o `gh issue new`, que una guarda quiere tras buscar en el backlog, sin clase, y recibe su plan después, como una enmienda con las cinco secciones y la línea de complejidad. <!-- p:planless-issue -->
- Lo que un trabajo deja para otra issue pasa por `trellis issue follow-up`. <!-- p:follow-up -->
- El pull request se abre como borrador. Se corre `trellis-plan-check` y después `gh pr ready`; una S que solo toca Markdown se lo salta. <!-- p:plan-check -->
- Su cuerpo lleva `Closes #<n>`, **Antes de mezclar** y **Después de mezclar**, cada una `nada` o una lista. <!-- p:pr-before-after -->
- Se mezcla con `/trellis-merge <pr>`. <!-- p:merge-skill -->
- Lo que el trabajo mezclado dejó pendiente: `gh issue list --state closed --label pending-actions`. <!-- p:pending-actions -->

<!-- /cycle -->
### Entregas

- Todo pull request es un incremento liberable. <!-- p:releasable -->
- Lo que espera una fecha sale activable por configuración. <!-- p:date-config -->
- Un backfill nunca deja una vista vacía entre el despliegue y un script. <!-- p:backfill -->
- Una prueba que el plan nombra se escribe aunque no se pueda correr en local, y el pull request dice qué escalón queda esperando. <!-- p:named-test -->
- Una barrera de calidad llega a la rama de release o no existe. El lint va dentro de la barrera: sacarlo por deriva acumulada es irreversible en la práctica. <!-- p:quality-barrier -->

### Subagentes

- Un subagente o una rutina recibe las reglas críticas en su prompt, sin pedirle leer lo que el arnés ya le carga. <!-- p:subagent-rules -->
- Su informe lleva un tope de longitud y es una afirmación que se verifica, no un hecho. <!-- p:subagent-report -->
- Comparte el sistema de ficheros: escribe con `mktemp`, y el padre usa nombres únicos. <!-- p:subagent-files -->
- Una búsqueda lleva un modelo barato. Trabajos hermanos van en pestañas, no en subagentes. <!-- p:cheap-search -->
