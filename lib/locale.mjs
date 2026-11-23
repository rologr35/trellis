// The language of what trellis writes into a project, from project.locale: en (the default) or es.
// One definition of the locale and of the pull request sections, read by lib/blocks.mjs,
// scripts/pr-check.mjs and scripts/ratchet.mjs.

export const LOCALES = ['en', 'es'];

/** The locale of a config: es when it says es, en otherwise. */
export const localeOf = config => (config.get('project.locale') === 'es' ? 'es' : 'en');

/** The sections `trellis pr-check` requires of a pull request body, and the setback, per locale. */
export const PR_SECTIONS = {
  en: {required: ['Summary', 'Verification'], setback: 'Setback', none: /^none\.?$/i},
  es: {required: ['Resumen', 'Verificación'], setback: 'Retroceso', none: /^nada\.?$/i},
};

/** The marker of a principle's id in method/<locale>.md, stripped from the generated block. */
export const PRINCIPLE_ID = / ?<!-- p:([a-z0-9-]+) -->/g;
