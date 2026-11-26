// The language of what trellis writes into a project, from project.locale: en (the default) or es.
// One definition of the locale, of the pull request sections and of the issue sections, read by
// lib/blocks.mjs and by the scripts (pr-check, ratchet, issue-check, issue-close).

export const LOCALES = ['en', 'es'];

/** The locale a value of project.locale names: es when it says es, en otherwise. */
export const localeNamed = value => (value === 'es' ? 'es' : 'en');

/** The locale of a config. */
export const localeOf = config => localeNamed(config.get('project.locale'));

/**
 * The sections of a pull request body, per locale: the ones `trellis pr-check` requires of every one,
 * the setback, the two it requires besides of a cycle pull request, the word of an empty one, and the
 * words that open the comment with what is pending.
 */
export const PR_SECTIONS = {
  en: {
    required: ['Summary', 'Verification'],
    setback: 'Setback',
    none: /^none\.?$/i,
    beforeMerging: 'Before merging',
    afterMerging: 'After merging',
    noneWord: 'none',
    pending: 'Pending after merging',
  },
  es: {
    required: ['Resumen', 'Verificación'],
    setback: 'Retroceso',
    none: /^nada\.?$/i,
    beforeMerging: 'Antes de mezclar',
    afterMerging: 'Después de mezclar',
    noneWord: 'nada',
    pending: 'Pendiente tras mezclar',
  },
};

/**
 * The sections a pull request body has to have: the ones of `pr.section`, or the two of a locale when none
 * is set.
 */
export function requiredSections(config, locale = localeOf(config)) {
  const set = config.all('pr.section').filter(Boolean);
  return set.length > 0 ? set : PR_SECTIONS[locale].required;
}

/**
 * The lesson line of a pull request body, per locale: its label, and the three answers it takes. The last
 * two, of the project and of trellis, say what after a colon.
 */
export const LESSON = {
  en: {label: 'Lesson', none: 'none', local: 'local', framework: 'framework'},
  es: {label: 'Lección', none: 'ninguna', local: 'local', framework: 'marco'},
};

/** The sections of an issue's plan, in order, and the labels inside them, per locale. */
export const ISSUE = {
  en: {
    sections: ['Context', 'Approved plan', 'Layers and files', 'Risks', 'Verification'],
    complexity: 'Complexity',
    outOfScope: 'Out of scope',
    source: 'Source',
    newFiles: 'New',
    dependsOn: 'Depends on',
    gates: 'Gates',
    noGates: 'none',
    needs: 'Needs',
    reopen: 'Reopen',
    none: /^none\.?$/i,
    amendment: 'Amendment',
  },
  es: {
    sections: ['Contexto', 'Plan aprobado', 'Capas y ficheros', 'Riesgos', 'Verificación'],
    complexity: 'Complejidad',
    outOfScope: 'Fuera de alcance',
    source: 'Fuente',
    newFiles: 'Nuevos',
    dependsOn: 'Depende de',
    gates: 'Gates',
    noGates: 'ninguno',
    needs: 'Necesita',
    reopen: 'Reabrir',
    none: /^(?:nada|ningun[oa])\.?$/i,
    amendment: 'Enmienda',
  },
};

/** The sections of the comment of `trellis issue stop`, and what it says of a plan nobody started, per locale. */
export const STOP = {
  en: {
    sections: ['Done', 'Missing', 'Needs'],
    notStarted: 'the whole plan: `trellis issue claim --unattended` refused it',
    started: branches => `what is in \`${branches}\`, which its stop before this one says`,
    rest: 'the rest of the plan: `trellis issue claim --unattended --resume` refused it',
  },
  es: {
    sections: ['Hecho', 'Falta', 'Necesita'],
    notStarted: 'todo el plan: `trellis issue claim --unattended` lo rechazó',
    started: branches => `lo que hay en \`${branches}\`, que dice su parada anterior`,
    rest: 'el resto del plan: `trellis issue claim --unattended --resume` lo rechazó',
  },
};

/**
 * What the hooks of a session without a person say, per locale: the reason hooks/unattended.sh gives Claude
 * for a question or a permission it refuses, and the section Missing of the stop hooks/waiting.sh writes.
 */
export const UNATTENDED = {
  en: {
    reason: 'No person answers this session: what needs one is a stop, never a question. When the instructions of this run name a stop of their own, make that one and end the run. When they name none, write a file with the sections **Done** (what the branch holds), **Missing** (the steps left) and **Needs** (what a person gives), `none` in one with nothing, run `trellis issue stop <n> --body-file <file>`, and end the run, as the skill trellis-work says.',
    waiting: type => `the run waits for a person (\`${type}\`)`,
  },
  es: {
    reason: 'Ninguna persona responde a esta sesión: lo que necesita una es una parada, nunca una pregunta. Cuando las instrucciones de esta ejecución nombran una parada propia, haz esa y termina la ejecución. Cuando no nombran ninguna, escribe un fichero con las secciones **Hecho** (lo que tiene la rama), **Falta** (los pasos que quedan) y **Necesita** (lo que da una persona), `nada` en la que no tenga nada, ejecuta `trellis issue stop <n> --body-file <file>` y termina la ejecución, como dice la skill trellis-work.',
    waiting: type => `la ejecución espera a una persona (\`${type}\`)`,
  },
};

/** The words of the report of agents/plan-check.md, per locale, in the order of its table. */
export const PLAN_CHECK = {
  en: {
    verdict: 'Verdict',
    satisfied: 'satisfied',
    changesRequested: 'changes requested',
    steps: 'Steps',
    outOfScope: 'Out of scope',
    files: 'Files',
    tests: 'Tests',
    gates: 'Gates',
    claims: 'Claims',
    notEstablished: 'Not established',
  },
  es: {
    verdict: 'Veredicto',
    satisfied: 'satisfecho',
    changesRequested: 'cambios pedidos',
    steps: 'Pasos',
    outOfScope: 'Fuera de alcance',
    files: 'Ficheros',
    tests: 'Pruebas',
    gates: 'Gates',
    claims: 'Afirmaciones',
    notEstablished: 'No establecido',
  },
};

/** The Cycle section of method/<locale>.md, with its markers: $1 is the section. */
export const CYCLE = /<!-- cycle -->\n([\s\S]*?)<!-- \/cycle -->\n/g;

/** The marker of a principle's id in method/<locale>.md, stripped from the generated block. */
export const PRINCIPLE_ID = / ?<!-- p:([a-z0-9-]+) -->/g;
