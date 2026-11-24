// The language of what trellis writes into a project, from project.locale: en (the default) or es.
// One definition of the locale, of the pull request sections and of the issue sections, read by
// lib/blocks.mjs, scripts/pr-check.mjs, scripts/ratchet.mjs and scripts/issue-check.mjs.

export const LOCALES = ['en', 'es'];

/** The locale of a config: es when it says es, en otherwise. */
export const localeOf = config => (config.get('project.locale') === 'es' ? 'es' : 'en');

/** The sections `trellis pr-check` requires of a pull request body, and the setback, per locale. */
export const PR_SECTIONS = {
  en: {required: ['Summary', 'Verification'], setback: 'Setback', none: /^none\.?$/i},
  es: {required: ['Resumen', 'Verificación'], setback: 'Retroceso', none: /^nada\.?$/i},
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
    amendment: 'Amendment',
  },
  es: {
    sections: ['Contexto', 'Plan aprobado', 'Capas y ficheros', 'Riesgos', 'Verificación'],
    complexity: 'Complejidad',
    outOfScope: 'Fuera de alcance',
    source: 'Fuente',
    newFiles: 'Nuevos',
    dependsOn: 'Depende de',
    amendment: 'Enmienda',
  },
};

/** The Cycle section of method/<locale>.md, with its markers: $1 is the section. */
export const CYCLE = /<!-- cycle -->\n([\s\S]*?)<!-- \/cycle -->\n/g;

/** The marker of a principle's id in method/<locale>.md, stripped from the generated block. */
export const PRINCIPLE_ID = / ?<!-- p:([a-z0-9-]+) -->/g;
