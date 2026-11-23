# trellis

Un arnés agéntico replicable para Claude Code: el método de trabajo siempre cargado, guardas de git, higiene de los ficheros de instrucciones, trinquetes y plantillas de proyecto. Este repositorio es a la vez el plugin y su marketplace.

Base, el módulo de este repositorio, solo necesita git y node. Los módulos Ciclo (issues, labels, revisión contra el plan) y Autonomía (rutinas en la nube, despachador, presupuesto) se construyen encima.

## Instalar en un proyecto

1. Claude Code 2.1.324 o posterior (el marketplace fijado por sha lo necesita).
2. En el proyecto: `/plugin marketplace add rologr35/trellis` y `/plugin install trellis@trellis`. `enabledPlugins` de `settings.json` habilita un plugin instalado, no lo instala.
3. `/trellis:init`: entrevista, escribe la configuración y las plantillas, y termina con `trellis sync`, `trellis hygiene --freeze` y `trellis doctor`.

`init` fija el marketplace en `.claude/settings.json` con el sha completo del plugin y `autoUpdate: false`, y el workflow del CI con el mismo sha. Actualizar el plugin es cambiar ese sha en los dos sitios, en un pull request propio.

## Qué hay

| Pieza | Dónde | Qué hace |
|---|---|---|
| Método | `method/base.md` | Cómo trabaja Claude, en cada turno. `trellis sync` lo copia en el bloque `<!-- trellis:method -->` del `CLAUDE.md` raíz, y la higiene comprueba que coincide: un skill solo carga cuando se invoca, el método se necesita siempre. |
| CLI | `bin/trellis` | `config`, `doctor`, `sync`, `hygiene`, `setup`, `worktree add\|prune`, `ratchet`, `pr-check`, `check`. |
| Configuración | `trellis.config` del proyecto | Formato git-config, leído con `git config -f`; `lib/schema` tiene las claves y sus valores por defecto. |
| Guardas | `hooks/guard-git.sh` | Push a ramas protegidas, cambios de rama en el checkout principal, issues sin búsqueda previa, merges fuera de las bases permitidas. |
| Git hooks | `templates/githooks/` | Trinquete, higiene, mensaje de commit y nombre de rama, en el clon. |
| CI del consumidor | `.github/workflows/consumer-check.yml` | Higiene, trinquete, `pr-check` y escáner de secretos en cada pull request. |
| Skills | `skills/` | `init`, `scaffold`, `debugging`, `retro`. |
| Agent | `agents/plan-reviewer.md` | Comprueba un plan contra el repositorio, en contexto limpio. |

## Dónde corre cada cosa

- `bin/` del plugin entra en el PATH del Bash tool de Claude, no en la shell de una persona ni en los hooks. Una persona o un git hook llama a `trellis` por su ruta: `lib/find-trellis.sh` la busca en el PATH y después en el `installPath` de `~/.claude/plugins/installed_plugins.json`, porque la ruta del caché cambia con cada versión.
- Los hooks del plugin usan `${CLAUDE_PLUGIN_ROOT}` y necesitan node. Sin node, `guard-git` queda sin opinión y `trellis doctor` da FAIL. El binario nativo de `claude` no trae node.
- Un plugin no aporta `permissions`: el `deny` vive en el `settings.json` del proyecto, y `trellis sync` lo genera.
- Una sesión alojada en la nube lee el `settings.json` del proyecto pero no añade los marketplaces de `extraKnownMarketplaces`, así que los hooks del plugin pueden no correr allí. Por eso el `deny` de push está en `settings.json` además de en `guard-git`.

## Las barreras y sus límites

- **CI del consumidor**: la barrera real, donde el plan de GitHub permite exigir checks. En un repositorio privado de un plan sin checks requeridos es consultivo: nada impide mezclar con un check en rojo. Quedan `guard-git` y el `deny` para Claude, los git hooks para el clon, y la persona que no mezcla en rojo. `trellis doctor` no puede saber qué plan tiene el repositorio.
- **Git hooks**: comodidad, no barrera. Un clon sin Claude y sin `init` no los tiene hasta que alguien corre `trellis setup`; el hook `SessionStart` del plugin lo corre en cada sesión, también en la nube. Los límites agregados (el total de las rules) corren solo en CI: son un presupuesto compartido entre ramas.
- **Push sin refspec**: el `deny` de `settings.json` cubre las formas que una regla de permisos puede expresar (`main`, `+main`, `refs/heads/main`, `HEAD:main`, con o sin `-C`), pero no `git push` a secas en una rama protegida: no hay patrón que lo pare sin parar todo push. Ahí la guarda es `guard-git`, que juzga la rama actual y su upstream; donde el plugin no carga, el método pide refspec explícito.
- **Merge**: solo `guard-git` juzga la base de un pull request. Un `deny` de `gh pr merge` bloquearía todos los merges o ninguno, porque una regla de permisos no ve la base y un `deny` gana a todo `allow`. Donde el plugin no carga, el merge queda sin guarda; Base no lanza sesiones en la nube.
- **Escáner de secretos**: una herramienta externa elegida en `init` (gitleaks por defecto). Sin ninguno configurado, `doctor` avisa; configurado y ausente, FAIL.

## Lo que el marco no hace, y por qué

- **Subagentes ejecutores que releen el repositorio.** Un subagente arranca sin el contexto de la sesión y lo reconstruye leyendo, lo que cuesta cupo cada vez. Base usa un solo subagente, `plan-reviewer`, porque un contexto limpio es justo lo que su comprobación necesita.
- **Comentarios de estado en las issues.** El estado de un trabajo vive en su rama, sus commits y su pull request; un comentario de estado es una segunda copia que envejece.
- **Reconciliación al iniciar sesión.** Releer todo el estado al arrancar paga en cada sesión lo que pocas necesitan. El estado se relee de su fuente cuando se usa.
- **Rituales de cierre.** Un paso fijo al terminar se salta cuando no aporta. `retro` propone una lección solo cuando la hay, y una persona la aplica.

## Desarrollo

```sh
for t in lib/*.test.sh scripts/*.test.sh hooks/*.test.sh; do /bin/bash "$t" || break; done
node --test hygiene/*.test.mjs
```

Los scripts corren con bash 3.2 (el de macOS): sin `mapfile`, sin arrays asociativos, y los arrays vacíos con `set -u` se expanden con cuidado. El CI corre en ubuntu y macos, y en macos con `/bin/bash`.

## Versión

`version` de `.claude-plugin/plugin.json` y un tag por versión. Un consumidor fija el sha, no el tag.
