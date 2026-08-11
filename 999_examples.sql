/*
 * keen-docs example content
 * =========================
 *
 * Seed data that exercises all three doc_set kinds, recreated on every `make setup`
 * (fullService drops + rebuilds the DB, so these idempotent ensure_* calls re-run).
 * This stands in for what the `keendocs` publish CLI will eventually push — it is NOT
 * schema, so it lives at the end (999), after the 100 content domain.
 *
 * Runs last; the post-update 99_fix_permissions.sql then reassigns ownership/grants.
 *
 * Component: keen_docs_examples
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

select *
from public.start_version_update('1',
    'keen-docs example content',
    _component := 'keen_docs_examples',
    _description := 'sample component / infrastructure / guide doc_sets');

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. COMPONENT set: web-multiselect (npm) — the FULLY-SPECIFIED reference doc_set.
--    Everything a single doc site configures (the keen-docs equivalent of one
--    mkdocs.yml) lives on the set: title + description, a home page, the settings
--    blob (theme / header + footer links / social / generator), and a navigation
--    tree in public.doc_nav (seeded further down). See ../postgresql-permissions-model-docs.
-- ─────────────────────────────────────────────────────────────────────────────
select * from public.ensure_doc_set('examples', 'seed', 'web-multiselect',
    _title       := 'Web MultiSelect',
    _kind_code   := 'component',
    _description := 'A lightweight, themeable multi-select web component — typeahead, virtual scroll, trees, RTL and full keyboard navigation.',
    _home_slug   := 'index',
    _settings    := $settings$
    {
      "author": "KeenMate",
      "site_url": "https://web-multiselect.keenmate.dev",
      "repository": "https://github.com/keenmate/web-multiselect",
      "theme":  { "accent": "#4f46e5", "logo": "assets/logo.svg", "favicon": "assets/logo.svg" },
      "header_links": [
        { "label": "GitHub", "url": "https://github.com/keenmate/web-multiselect", "icon": "github" },
        { "label": "npm",    "url": "https://www.npmjs.com/package/@keenmate/web-multiselect", "icon": "npm" }
      ],
      "footer": {
        "copyright": "© KeenMate. MIT-licensed.",
        "links": [
          { "label": "Theme Designer", "url": "https://theme-designer.keenmate.dev" },
          { "label": "All components",  "url": "https://docs.keenmate.dev" }
        ]
      },
      "social":      [ { "icon": "globe", "url": "https://keenmate.com", "name": "KeenMate" } ],
      "head_assets": [ { "rel": "preconnect", "href": "https://cdn.jsdelivr.net" } ],
      "generator":   false
    }
    $settings$::jsonb);
select * from public.ensure_doc_set_package('examples', 'seed', 'web-multiselect', 'npm', '@keenmate/web-multiselect', true);

-- v2.0.0 — stable, the default landing version, covers the whole 2.x line.
select * from public.ensure_doc_variant('examples', 'seed', 'web-multiselect', '2.0.0',
    _title := 'v2.0.0', _is_default := true, _show_in_path := true, _sort_order := 200,
    _maturity_code := 'stable',
    _applies_to := '[{"range": "^2.0.0", "from": "2.0.0", "to": "3.0.0"}]'::jsonb);

-- v3.0.0-rc1 — pre-release, reachable but never the default.
select * from public.ensure_doc_variant('examples', 'seed', 'web-multiselect', '3.0.0-rc1',
    _title := 'v3.0.0-rc1', _is_default := false, _show_in_path := true, _sort_order := 300,
    _maturity_code := 'rc',
    _applies_to := '[{"range": "3.0.0-rc*", "from": "3.0.0", "to": "3.0.1"}]'::jsonb);

-- A hidden 'shared' variant (show_in_path = false) holds DOC-SET-WIDE pages — content that
-- belongs to the whole component, not one version (changelog, migration). Its URL omits the
-- version segment (/web-multiselect/changelog), and being off-path it is NOT a version, so
-- the sidebar's version selector skips it.
select * from public.ensure_doc_variant('examples', 'seed', 'web-multiselect', 'shared',
    _title := 'shared', _is_default := false, _show_in_path := false, _sort_order := 0);

-- Rich pages: the stored blob is the whole .md (front matter + body exercising the
-- directive vocabulary — callout / columns / col / card / showcase / tables / fences).
-- The full-text index is built from the readable prose + the front-matter keywords, so
-- searching for "accessibility" or "keyboard" hits even though neither word is a heading.
select * from public.ensure_document('examples', 'seed', 'web-multiselect', '2.0.0', 'index', 'Overview',
    _content := $md$---
title: Overview
description: A typeahead multiselect web component — accessible, framework-free, and form-ready.
keywords: [multiselect, typeahead, autocomplete, dropdown, accessibility, keyboard, web component]
nav: 1
---

`<web-multiselect>` is a **standalone custom element**: drop the tag on any page — no
framework, no build step — and it upgrades into an accessible multi-value picker with
typeahead search and full keyboard navigation.

:::callout{type=info title="Zero dependencies"}
It ships as one ES module and a stylesheet. Because it is a real custom element it works
the same in plain HTML, React, Vue, or a server-rendered page.
:::

:::columns{cols="60/40"}

:::col{title="What you get"}
- Typeahead filtering over large option lists
- Keyboard-first: arrow keys, <kbd>Enter</kbd>, <kbd>Esc</kbd>, type-to-filter
- A hidden input that stays in sync for native form submits
- Screen-reader announcements via ARIA roles
:::

:::col{title="Install"}
:::code{lang=bash}
npm install @keenmate/web-multiselect
:::

Then import it once, anywhere in your bundle:

:::code{lang=js}
import '@keenmate/web-multiselect';
:::
:::

:::

## Anatomy

:::card{title="One tag, three attributes"}
Options come from `data-options`, the submitted field name from `name`, and how the value
is serialized from `value-format`. Everything else has sensible defaults.
:::

| Attribute | Purpose | Default |
| --- | --- | --- |
| `data-options` | comma-separated choices | — |
| `name` | form field name for the hidden input | none |
| `value-format` | `json` / `csv` / `array` | `json` |

See [Form integration](form-integration) for the value formats in depth.
$md$,
    _frontmatter := '{"nav": 1, "description": "A typeahead multiselect web component — accessible, framework-free, and form-ready.", "keywords": ["multiselect", "typeahead", "autocomplete", "dropdown", "accessibility", "keyboard", "web component"]}'::jsonb);

select * from public.ensure_document('examples', 'seed', 'web-multiselect', '2.0.0', 'form-integration', 'Form integration',
    _content := $md$---
title: Form integration
description: Submit multiselect values with native HTML forms — no JavaScript glue required.
keywords: [forms, hidden input, submit, validation, json, csv, serialization]
nav: 2
uses: "@keenmate/web-multiselect"
version: "2.0.0-rc01"
cdn:
  script: "dist/multiselect.js"
  style: "dist/style.css"
---

To integrate the multiselect with HTML forms you set the `name` attribute. The component
keeps a hidden input in sync as the selection changes, so a normal form **submit** carries
the value with no JavaScript glue.

:::callout{type=info title="Try it"}
The demo below is a real `<web-multiselect>` — selecting items runs live JS and prints the
value the server would receive. Press <kbd>Esc</kbd> to close the dropdown.
:::

## FI01 — JSON format (default)

:::showcase{title="FI01 JSON Format" subtitle="Hidden input with a JSON array value"}

:::col{title="Demo"}
:::demo
<web-multiselect name="languages" value-format="json">
  <option value="js">JavaScript</option>
  <option value="ts">TypeScript</option>
  <option value="py">Python</option>
  <option value="go">Go</option>
  <option value="rs">Rust</option>
  <option value="ex">Elixir</option>
</web-multiselect>
:::
:::run
el.addEventListener('change', (e) => out({
  values: e.detail.selectedValues,
  selected: e.detail.selectedOptions.map(o => o.label)
}));
:::
:::

:::col{title="Description"}
Creates a **single** hidden input whose value is a JSON array. Best for modern backends
that parse a JSON body.
:::

:::

## Big demos want more room

Layout is a generic primitive — this is an **80/20** split, impossible with a fixed
12-column grid:

:::columns{cols="80/20"}

:::col{title="Demo"}
:::demo
<web-multiselect value-format="csv" data-options-format="plain"
  data-options="Prague,Vienna,Berlin,Warsaw,Budapest"></web-multiselect>
:::
:::

:::col{title="Notes"}
Typeahead, keyboard nav and the CSV value format — all from plain attributes.
:::

:::

## Value formats

| `value-format` | Hidden input value | Use when |
| --- | --- | --- |
| `json` | `["js","ts"]` | modern JSON backends |
| `csv` | `js,ts` | classic form posts |
| `array` | repeated `name[]` inputs | PHP-style arrays |

## Put it in a form

No JavaScript required — wrap the element in a `<form>` and its hidden input is submitted
like any other field:

:::code{lang=html}
<form method="post" action="/profile">
  <label>Languages you know
    <web-multiselect name="languages" value-format="json">
      <option value="js">JavaScript</option>
      <option value="ts">TypeScript</option>
      <option value="ex" selected>Elixir</option>
    </web-multiselect>
  </label>
  <button type="submit">Save</button>
</form>
:::

## Read it on the server

The selection arrives as a normal form field named `languages`; parse it by the
`value-format` you chose:

:::code{lang=js}
// value-format="json" — one field, a JSON array string
app.post('/profile', (req, res) => {
  const languages = JSON.parse(req.body.languages); // ["js", "ts", "ex"]
});
:::

:::code{lang=js}
// value-format="csv" — one field, comma-separated
const languages = req.body.languages.split(',');    // ["js", "ts", "ex"]
:::

:::code{lang=php}
// value-format="array" — repeated name[] inputs (classic PHP arrays)
$languages = $_POST['languages'];                    // ['js', 'ts', 'ex']
:::

## Or drive it from JavaScript

Set options and read the selection through the element's properties and its `change` event:

:::code{lang=js}
const el = document.querySelector('web-multiselect');

el.options = [
  { value: 'js', label: 'JavaScript' },
  { value: 'ts', label: 'TypeScript' },
];

el.addEventListener('change', (e) => {
  console.log(e.detail.selectedValues);   // ['js']
  console.log(e.detail.selectedOptions);  // [{ value: 'js', label: 'JavaScript' }]
});
:::

:::card{title="Tip"}
`:::col` is a plain labelled column (no box); `:::card` — like this one — is the boxed
variant, and it can sit inside a column.
:::
$md$,
    _frontmatter := '{"nav": 2, "description": "Submit multiselect values with native HTML forms — no JavaScript glue required.", "keywords": ["forms", "hidden input", "submit", "validation", "json", "csv", "serialization"]}'::jsonb);

-- Island page: mounts the REAL published keen-phoenix-svelte apps, imported :direct from
-- the external CDN apps.keen-phoenix-svelte.keenmate.dev. Bundle URLs come from this page's
-- front-matter `apps:` map; the harness serves only the client runtime (/apps_runtime.js),
-- and mountStatic() mounts them on this plain (non-LiveView) page.
select * from public.ensure_document('examples', 'seed', 'web-multiselect', '2.0.0', 'islands', 'Interactive islands',
    _content := $md$---
title: Interactive islands
description: Mount real, published keen-phoenix-svelte islands from an external CDN — live, on a plain page.
keywords: [island, keen-phoenix-svelte, interactive, app, mount, svelte, cdn, external, dashboard, metrics]
nav: 3
apps:
  hello: "https://apps.keen-phoenix-svelte.keenmate.dev/hello/main.mjs"
  metrics: "https://apps.keen-phoenix-svelte.keenmate.dev/metrics/main.mjs"
  dashboard: "https://apps.keen-phoenix-svelte.keenmate.dev/dashboard/main.mjs"
---

Most demos are markup plus a CDN web component. The rare case — an inline editor, a live
dashboard — needs a **compiled bundle** with an `api` / `live` / `channel` / `bus` bridge.
Those are keen-phoenix-svelte **islands**, authored as `:::app`.

:::callout{type=info title="Real apps, external origin, plain page"}
Every island below is imported **direct** from `apps.keen-phoenix-svelte.keenmate.dev` — a
genuinely external CDN, a different host from this server. No LiveView: the client runtime's
`mountStatic()` mounts them here, reading the `#keen-apps` manifest and context this page emits.
:::

## hello — a single-file island

The simplest island: one self-contained module, its CSS injected by JS. It reads a
`greeting_name` prop.

:::app{name="hello"}

:::props
```json
{ "greeting_name": "keen-docs" }
```
:::

:::placeholder
Loading hello…
:::

:::

## metrics — a multi-file island

Its entry resolves its stylesheet and seed JSON **relative to itself** (`import.meta.url`),
so the same bytes work whether imported direct from the CDN or re-served through a proxy.

:::app{name="metrics"}

:::placeholder
Loading metrics…
:::

:::

## dashboard — a code-split island

A small entry that lazy-`import()`s its view chunks (`overview`, `charts`, `table`) on
demand, plus a stylesheet, an SVG asset and seed data — all fetched from the CDN.

:::app{name="dashboard"}

:::placeholder
Loading dashboard…
:::

:::

Bundle URLs come from this page's front-matter `apps:` map; each `:::app{name=…}` mounts one.
Swap `mode: :proxy` in a real Phoenix app to re-serve them same-origin under a strict CSP.
$md$,
    _frontmatter := '{"nav": 3, "description": "Mount real, published keen-phoenix-svelte islands from an external CDN — live, on a plain page.", "keywords": ["island", "keen-phoenix-svelte", "interactive", "app", "mount", "svelte", "cdn", "external", "dashboard", "metrics"]}'::jsonb);

select * from public.ensure_document('examples', 'seed', 'web-multiselect', '3.0.0-rc1', 'index', 'Overview (3.0 preview)',
    _content := $md$---
title: Overview (3.0 preview)
description: The 3.0 line rebuilds the internals on signals for fine-grained reactivity.
keywords: [signals, reactivity, preview, release candidate, migration]
nav: 1
---

# Web MultiSelect 3.0

:::callout{type=warning title="Pre-release"}
3.0 is a **release candidate**. The public attribute API is stable, but internals are
still moving — pin an exact version if you depend on it.
:::

The 3.0 line rebuilds the component on a **signals**-based core for fine-grained
reactivity, cutting re-renders on large option sets.
$md$,
    _frontmatter := '{"nav": 1, "description": "The 3.0 line rebuilds the internals on signals for fine-grained reactivity.", "keywords": ["signals", "reactivity", "preview", "release candidate", "migration"]}'::jsonb);

-- Doc-set-wide pages: stored in the hidden 'shared' variant, so they are reachable at
-- /web-multiselect/changelog and /web-multiselect/migration regardless of the active version.
select * from public.ensure_document('examples', 'seed', 'web-multiselect', 'shared', 'changelog', 'Changelog',
    _content := $md$---
title: Changelog
description: Notable changes across web-multiselect releases.
keywords: [changelog, releases, history, breaking changes]
---

# Changelog

A **doc-set-wide** page — one changelog for the whole component, reachable at
`/web-multiselect/changelog` no matter which version you are viewing. It lives in the hidden
`shared` variant, not under a version.

## 2.0.0 — core adoption

- Rebuilt on `@keenmate/web-components-core` (`BlissElement`).
- **Breaking:** `onSelect` / `onDeselect` / `onChange` are event-handler properties.
- **Breaking:** property writes are async (coalesced) — `await el.whenSettled()`.
- `data-options` gains `csv` and `plain` formats with configurable delimiters.

## 1.12.0

- Independent dropdown / popover sizing via `--ms-dropdown-width`.
- Tree render callback receives full tree context (`isBranch`, `level`, `path`, …).
$md$);

select * from public.ensure_document('examples', 'seed', 'web-multiselect', 'shared', 'migration', 'Migration v1 → v2',
    _content := $md$---
title: Migration v1 → v2
description: The breaking API changes in the v2 core-adoption major, and how to update.
keywords: [migration, upgrade, breaking changes, v2]
---

# Migration: v1 → v2

Also a **doc-set-wide** page — migration is about moving *between* versions, so it is authored
once for the whole set rather than inside a version folder.

:::callout{type=info title="Why this is version-independent"}
It describes the jump from v1 to v2, so it does not belong to either version's page tree — it
belongs to the component.
:::

## 1. Handlers receive the event

`onChange` receives the `CustomEvent` now — read `e.detail.selectedValues`:

:::code{lang=js}
el.onChange = (e) => save(e.detail.selectedValues);
:::

## 2. setAttributes takes typed camelCase keys

:::code{lang=js}
el.setAttributes({ searchPlaceholder: 'Search…', isCounterShown: true });
:::
$md$);

-- Navigation tree (public.doc_nav) — the authored sidebar, mirroring an mkdocs `nav:`.
-- Parents are ensured before children (full_title / sort_key derive from the parent). Leaves
-- carry a slug (resolved against the active variant); sections carry none. Nesting is a '/'
-- in the node path; sort_order orders siblings. get_doc_nav('web-multiselect') then returns
-- these already in render order — a single ordered select, no recursion.
--
--   Project                         (section)   -- leads the sidebar
--     Overview                       (leaf → index, versioned)
--     Changelog                      (leaf → changelog, shared)
--     Migration v1 → v2              (leaf → migration, shared)
--   Guides                          (section)
--     Form integration              (leaf → form-integration)
--   Live demos                      (section)
--     Interactive islands           (leaf → islands)
-- Project section leads and holds Overview + the DOC-SET-WIDE leaves (changelog/migration pin
-- _variant_code := 'shared', so they link to /web-multiselect/changelog under every version).
select * from public.ensure_doc_nav('examples', 'seed', 'web-multiselect', 'project', 'Project',
    _is_section := true, _sort_order := 0);
select * from public.ensure_doc_nav('examples', 'seed', 'web-multiselect', 'project/overview', 'Overview',
    _slug := 'index', _sort_order := 0);
select * from public.ensure_doc_nav('examples', 'seed', 'web-multiselect', 'project/changelog', 'Changelog',
    _slug := 'changelog', _variant_code := 'shared', _sort_order := 1);
select * from public.ensure_doc_nav('examples', 'seed', 'web-multiselect', 'project/migration', 'Migration v1 → v2',
    _slug := 'migration', _variant_code := 'shared', _sort_order := 2);

select * from public.ensure_doc_nav('examples', 'seed', 'web-multiselect', 'guides', 'Guides',
    _is_section := true, _sort_order := 1);
select * from public.ensure_doc_nav('examples', 'seed', 'web-multiselect', 'guides/forms', 'Form integration',
    _slug := 'form-integration', _sort_order := 0);

select * from public.ensure_doc_nav('examples', 'seed', 'web-multiselect', 'demos', 'Live demos',
    _is_section := true, _sort_order := 2);
select * from public.ensure_doc_nav('examples', 'seed', 'web-multiselect', 'demos/islands', 'Interactive islands',
    _slug := 'islands', _sort_order := 0);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. INFRASTRUCTURE set: azure / aws divisions, no versions, no package
-- ─────────────────────────────────────────────────────────────────────────────
select * from public.ensure_doc_set('examples', 'seed', 'infrastructure', 'Infrastructure', 'infrastructure');

select * from public.ensure_doc_variant('examples', 'seed', 'infrastructure', 'azure',
    _title := 'Azure', _is_default := true, _show_in_path := true, _sort_order := 20);
select * from public.ensure_doc_variant('examples', 'seed', 'infrastructure', 'aws',
    _title := 'AWS', _is_default := false, _show_in_path := true, _sort_order := 10);

select * from public.ensure_document('examples', 'seed', 'infrastructure', 'azure', 'networking', 'Azure networking',
    E'# Azure networking\n\nVNets, subnets and NSGs govern traffic between workloads.',
    '{"description": "Virtual networks, subnets and network security groups on Azure.", "keywords": ["vnet", "subnet", "nsg", "firewall", "networking"]}'::jsonb);
select * from public.ensure_document('examples', 'seed', 'infrastructure', 'aws', 'networking', 'AWS networking',
    E'# AWS networking\n\nVPCs, subnets and security groups govern traffic between workloads.',
    '{"description": "Virtual private clouds, subnets and security groups on AWS.", "keywords": ["vpc", "subnet", "security group", "firewall", "networking"]}'::jsonb);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. GUIDE set: flat, single 'main' variant with show_in_path = false (no version segment)
-- ─────────────────────────────────────────────────────────────────────────────
select * from public.ensure_doc_set('examples', 'seed', 'backend-guidelines', 'Backend Guidelines', 'guide');

select * from public.ensure_doc_variant('examples', 'seed', 'backend-guidelines', 'main',
    _title := 'Guide', _is_default := true, _show_in_path := false, _sort_order := 0);

select * from public.ensure_document('examples', 'seed', 'backend-guidelines', 'main', 'naming', 'Naming',
    E'# Naming\n\nTables are **singular**; prefer explicit names over convention.',
    '{"description": "Naming rules: singular tables, explicit over conventional.", "keywords": ["naming", "conventions", "tables", "style"]}'::jsonb);
select * from public.ensure_document('examples', 'seed', 'backend-guidelines', 'main', 'testing', 'Testing',
    E'# Testing\n\nEvery public function gets a **round-trip** test.',
    '{"description": "Testing rules: round-trip coverage for every public function.", "keywords": ["testing", "round-trip", "coverage", "quality"]}'::jsonb);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. HUB (global) SITE: the docs.keenmate.dev aggregate — its own landing, standalone
--    global pages, and a cross-set navigation. Parallels a doc_set but at the site level.
-- ─────────────────────────────────────────────────────────────────────────────
select * from public.ensure_site('examples', 'seed', 'hub',
    _title       := 'KeenMate Docs',
    _description := 'Component libraries, guides and infrastructure — documented in one place.',
    _home_slug   := 'index',
    _settings    := $settings$
    {
      "author": "KeenMate",
      "site_url": "https://docs.keenmate.dev",
      "theme":  { "accent": "#0ea5e9" },
      "footer": {
        "copyright": "© KeenMate. MIT-licensed.",
        "links": [ { "label": "keenmate.com", "url": "https://keenmate.com" } ]
      },
      "social": [ { "icon": "github", "url": "https://github.com/keenmate", "name": "GitHub" } ]
    }
    $settings$::jsonb);

-- Global standalone pages (site_page) — not under any doc_set.
select * from public.ensure_site_page('examples', 'seed', 'hub', 'index', 'KeenMate Docs',
    _content := $md$---
title: KeenMate Docs
description: Component libraries, guides and infrastructure — documented in one place.
keywords: [keenmate, documentation, components, guides, hub]
---

Everything KeenMate ships, documented in one place — live component demos, backend
guidelines, and infrastructure notes. The title above comes from the hub's own settings,
so the page body starts straight with content — no repeated heading.

:::columns{cols="4/4/4"}

:::card{title="Components"}
Live, themeable web components with real demos — starting with
[Web MultiSelect](/web-multiselect).
:::

:::card{title="Guides"}
Cross-cutting engineering guidance, like the [Backend Guidelines](/backend-guidelines).
:::

:::card{title="Infrastructure"}
Cloud and platform notes across [Azure and AWS](/infrastructure).
:::

:::

See [About](/about) for what this site is and how it is built.
$md$);

select * from public.ensure_site_page('examples', 'seed', 'hub', 'about', 'About',
    _content := $md$---
title: About
description: What KeenMate Docs is and how it is built.
keywords: [about, colophon, keen-docs, engine]
---

# About

**KeenMate Docs** is one multi-tenant site over every KeenMate library. Content is authored
as a custom markdown superset and rendered server-side; demos are real components, not images.

:::callout{type=info title="A global page"}
This page belongs to the whole site, not to any single doc_set — it lives in the hub's
`site_page` table and is reachable at `/about` from anywhere.
:::
$md$);

-- Global navigation (site_nav) — the top bar across doc sets. A leaf targets a site_page
-- (slug), a whole doc_set (doc_set_code → its homepage), or an external URL.
select * from public.ensure_site_nav('examples', 'seed', 'hub', 'components', 'Components',
    _is_section := true, _sort_order := 0);
select * from public.ensure_site_nav('examples', 'seed', 'hub', 'components/web-multiselect', 'Web MultiSelect',
    _doc_set_code := 'web-multiselect', _sort_order := 0);

select * from public.ensure_site_nav('examples', 'seed', 'hub', 'guides', 'Guides',
    _doc_set_code := 'backend-guidelines', _sort_order := 1);
select * from public.ensure_site_nav('examples', 'seed', 'hub', 'infrastructure', 'Infrastructure',
    _doc_set_code := 'infrastructure', _sort_order := 2);
select * from public.ensure_site_nav('examples', 'seed', 'hub', 'about', 'About',
    _slug := 'about', _sort_order := 3);
select * from public.ensure_site_nav('examples', 'seed', 'hub', 'github', 'GitHub',
    _url := 'https://github.com/keenmate', _sort_order := 4);

select * from public.stop_version_update('1', _component := 'keen_docs_examples');
