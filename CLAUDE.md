# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

This is a **copy of the `postgresql-permissions-model` test database, retargeted as the application
database for [keen-docs](../keen-docs)** (database name `keen_docs`). It holds two layers:

1. **The borrowed permission-model framework** — migrations `000`–`099` (common helpers, version
   management, `const`, `auth`, plus illustrative examples `010`/`012`/`013`). Treat these as vendored;
   don't edit them for keen-docs work. `readme.md` documents this framework in full.
2. **keen-docs' own content domain** — starts at `100`. This is what we build here.

## Layout & migration layering

Migrations are applied by **debee** and swept in order. A file is swept **only** if it matches
`^\d{3}_.*\.sql$` (exactly 3 digits + underscore).

| File | Role |
|------|------|
| `000_create_database.sql` | recreate script (`db_name` = `keen_docs`) |
| `001`–`009` | common framework (helpers, version management) — **don't touch** |
| `010`/`012`/`013` | framework examples (auth prereq, const, auth tables) — illustrative |
| `100_docs_content.sql` | **keen-docs content domain** (the schema we own) |
| `999_examples.sql` | **keen-docs example seed** (swept → recreated every `make setup`) |
| `99_fix_permissions.sql` | post-update script (2-digit → NOT swept; referenced by `debee.env` `DBPOSTUPDATESCRIPTS`). Grants + `REASSIGN OWNED` to the `keen_docs` role. |

Gotcha: a 3-digit-prefixed file is a migration. `099_fix_permissions.sql` was a duplicate that got
wrongly swept as migration #99 — it was deleted; the real post-update script is the 2-digit `99_`.

## Toolchain

- **debee** (`debee.py`/`.ps1`/`.sh`, all have `--llm`) orchestrates; all logic is in external `.sql`.
  Config: `debee.env` (base) ← `.debee.env` (local override, later wins; carries the real connection).
- **`make setup`** = `debee -o fullService` = recreate + restore + update + post-update. **Destructive**
  (drops/recreates `keen_docs`). Because it recreates, swept files (including `999_examples.sql`) re-run
  every time. `make update` = `updateDatabase` (no recreate). `make test` / `make sql` also via debee.
- **db-gen** runs from **[../keen-docs](../keen-docs)** (`make db-gen` there), not from here — it reads
  these stored functions and generates the Elixir wrappers. So the loop is: edit SQL here → `make setup`
  here → `make db-gen` in keen-docs.
- Both need the DB reachable — **VPN to `db-01.km8.local`**.

## Conventions for the content domain (`100_docs_content.sql`)

All SQL follows the **Bliss PostgreSQL guidelines** (`C:\Git\BlissFramework\web\docs\coding-guidelines-postgres`);
`postgresql-permissions-model` is the reference implementation — "when in doubt, do what it does".

- **Schemas as layers.** Main project tables go in **`public`** (KeenMate convention). `const` = lookup
  tables (FK, not enum/CHECK). Fully-qualify schema names in function bodies.
- **Naming.** Tables singular; `<table>_id generated always as identity`; universal audit columns
  (`created_at/by`, `updated_at/by`) — **first** in each table; `nrm_` normalized search columns;
  functions `verb_noun` from the shared **verb registry** (`get/search/create/update/delete/ensure/…` —
  `ensure` for idempotent upserts; **NOT** "ingest"/"package").
- **Underscore rule.** `_param` (input), `__local` / `returns table(...)` column, `___disambiguation`.
- **Search functions.** Two-jsonb signature: `_search_criteria` (what) + `_search_settings` (paging/order);
  parse leniently, **whitelist** `order_by` (no dynamic SQL).
- **Public-API types.** `public.*` params/returns use only stock PG types + `jsonb` — never expose
  `tsvector`/`ltree`/etc. (client codegen can't map them).
- **Migrations forward-only**, wrapped in `start_version_update`/`stop_version_update(_component := …)`.
  keen-docs' component is `keen_docs` (content) / `keen_docs_examples` (seed). Errors via
  `error.raise_NNNNN` once codes are allocated (until then, keep validation minimal — no inline `raise`).

The content model: `public.doc_set → doc_variant → document` + content-addressed `content_blob`;
`const` lookups `doc_set_kind` / `package_ecosystem` / `version_maturity`; `ensure_*` / `get_*` / `list_*`
/ `resolve_doc_variant` / `search_documents`. The middle layer is a **neutral `doc_variant`** (version /
division / hidden `main`) — see the top of `CHANGELOG.md` for the full description.

## Related

- [`../keen-docs`](../keen-docs) — the Elixir app that consumes this DB (db-gen + raw Postgrex, no Ecto)
- [`../keen-auth-permissions`](../keen-auth-permissions) — the app-layer pattern keen-docs mirrors
- `readme.md` — the underlying permission-model framework · `CHANGELOG.md` — keen-docs entry on top
