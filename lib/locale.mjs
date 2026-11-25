// The language of what trellis writes into a project, from project.locale: en (the default) or es.
// One definition of the locale, of the pull request sections and of the issue sections, read by
// lib/blocks.mjs and by the scripts (pr-check, ratchet, issue-check, issue-close).

export const LOCALES = ['en', 'es'];

/** The locale of a config: es when it says es, en otherwise. */
export const localeOf = config => (config.get('project.locale') === 'es' ? 'es' : 'en');

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
  },
  es: {
    sections: ['Hecho', 'Falta', 'Necesita'],
    notStarted: 'todo el plan: `trellis issue claim --unattended` lo rechazó',
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
