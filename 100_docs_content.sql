/*
 * keen-docs content domain
 * =========================
 *
 * A `doc_set` is any documented subject — a component library (web-multiselect), a
 * guidelines collection, an infrastructure area — discriminated by `kind_code`. Under
 * each set sits one or more `doc_variant`s: a NEUTRAL partition whose meaning follows
 * the set's kind —
 *     component      -> a VERSION   ('2.0.0'; carries applies_to + maturity)
 *     infrastructure -> a DIVISION  ('azure' / 'aws'; parallel, unordered)
 *     guide          -> a single default variant ('main'; show_in_path = false, so its
 *                       URL segment is omitted -> generic guides carry no version)
 * Documents (pages) hang off a variant; their bytes live once in a content-addressed
 * `content_blob`. Component sets also declare their package identity (npm/nuget/hex/…)
 * in `doc_set_package`, so an uploaded package.json/csproj/mix.exs resolves to the
 * right doc version via `applies_to`.
 *
 * Tables and their public API live in the `public` schema (main project tables go in
 * public); const lookups go in `const`. The 000-099 range is the borrowed
 * permission-model framework, so this app domain starts at 100.
 *
 * Layering note: reads/search/resolve are public content utilities (docs are public) so
 * they carry no permission check. Publishing (ensure_*) is a mutation that will move
 * behind an auth.* permission check + public.journal audit once API-key auth is wired.
 *
 * Component: keen_docs
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

select *
from public.start_version_update('1',
    'keen-docs content domain',
    _component := 'keen_docs',
    _description := 'public.doc_set/doc_set_package/doc_variant/document/content_blob + ensure/get/resolve/search');

-- ---------------------------------------------------------------------------
-- Lookups (const) — FK, not enum/CHECK, so new values are data not migrations
-- ---------------------------------------------------------------------------

-- What a doc_set *is* — drives rendering/routing.
create table if not exists const.doc_set_kind (
    code  text not null primary key,
    title text not null
);

insert into const.doc_set_kind (code, title) values
    ('component',      'Component library'),
    ('guide',          'Guide / guidelines'),
    ('infrastructure', 'Infrastructure documentation')
on conflict (code) do nothing;

-- How a documented thing is distributed — drives package detection, install snippets
-- and registry links. `manifest_file` is the file we parse from an uploaded project;
-- null (executable) = no manifest, so those sets get a manual version picker.
create table if not exists const.package_ecosystem (
    code                  text not null primary key,
    title                 text not null,
    manifest_file         text,
    install_template      text,
    registry_url_template text
);

insert into const.package_ecosystem (code, title, manifest_file, install_template, registry_url_template) values
    ('npm',       'Node.js / npm',   'package.json', 'npm install {name}@{version}',            'https://www.npmjs.com/package/{name}'),
    ('nuget',     'NuGet',           '*.csproj',     'dotnet add package {name} --version {version}', 'https://www.nuget.org/packages/{name}'),
    ('hex',       'Elixir / Hex',    'mix.exs',      '{:{name}, "~> {version}"}',                'https://hex.pm/packages/{name}'),
    ('go_module', 'Go module',       'go.mod',       'go get {name}@v{version}',                 'https://pkg.go.dev/{name}'),
    ('cargo',     'Rust / Cargo',    'Cargo.toml',   'cargo add {name}@{version}',               'https://crates.io/crates/{name}'),
    ('executable','Executable / CLI', null,           null,                                       null)
on conflict (code) do nothing;

-- Release maturity of a version-variant — `latest` picks the highest stable, so a
-- pre-release (rc/beta/alpha) is reachable but never the default.
create table if not exists const.version_maturity (
    code      text    not null primary key,
    title     text    not null,
    is_stable boolean not null default false
);

insert into const.version_maturity (code, title, is_stable) values
    ('stable',  'Stable',            true),
    ('rc',      'Release candidate', false),
    ('beta',    'Beta',              false),
    ('alpha',   'Alpha',             false),
    ('nightly', 'Nightly',           false)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- A documented subject. `code` is the URL slug (explicit + stable, independent of any
-- registry name); `kind_code` decides how its variants are interpreted.
create table if not exists public.doc_set (
    created_at timestamp with time zone default now()           not null,
    created_by text                     default 'unknown'::text not null,
    updated_at timestamp with time zone default now()           not null,
    updated_by text                     default 'unknown'::text not null,
    doc_set_id integer generated always as identity primary key,
    code       text not null,
    kind_code  text not null default 'component' references const.doc_set_kind,
    title      text
);

create unique index if not exists uq_doc_set_code on public.doc_set (code);

-- Package identity of a set (0..n): the same subject may ship to several registries, or
-- none (guides/infra). `package_name` is the registry id (@keenmate/web-multiselect,
-- KeenMate.X, github.com/keenmate/…). A registry package maps to exactly one set.
create table if not exists public.doc_set_package (
    created_at         timestamp with time zone default now()           not null,
    created_by         text                     default 'unknown'::text not null,
    updated_at         timestamp with time zone default now()           not null,
    updated_by         text                     default 'unknown'::text not null,
    doc_set_package_id integer generated always as identity primary key,
    doc_set_id         integer not null references public.doc_set,
    ecosystem_code     text    not null references const.package_ecosystem,
    package_name       text    not null,
    is_primary         boolean not null default false
);

create unique index if not exists uq_doc_set_package on public.doc_set_package (ecosystem_code, package_name);
create index        if not exists ix_doc_set_package_set on public.doc_set_package (doc_set_id);

-- A neutral partition of a set. For a component it's a version (applies_to + maturity);
-- for infrastructure a division (azure/aws); for a guide the single 'main' variant with
-- show_in_path = false (its URL segment is omitted). `content_sha` is the whole-variant
-- hash from the publish CLI (dedup key at variant granularity).
create table if not exists public.doc_variant (
    created_at    timestamp with time zone default now()           not null,
    created_by    text                     default 'unknown'::text not null,
    updated_at    timestamp with time zone default now()           not null,
    updated_by    text                     default 'unknown'::text not null,
    doc_variant_id integer generated always as identity primary key,
    doc_set_id     integer not null references public.doc_set,
    code           text    not null,
    title          text,
    is_default     boolean not null default false,
    show_in_path   boolean not null default true,
    sort_order     integer not null default 0,
    maturity_code  text    references const.version_maturity,
    applies_to     jsonb,
    content_sha    text
);

create unique index if not exists uq_doc_variant on public.doc_variant (doc_set_id, code);

-- Content-addressed blob store: a file's bytes are stored once per sha, deduped across
-- every variant and set that contains them. Immutable, so no updated_* columns.
create table if not exists public.content_blob (
    created_at timestamp with time zone default now()           not null,
    created_by text                     default 'unknown'::text not null,
    sha        text   not null primary key,
    byte_size  bigint not null,
    content    bytea  not null
);

-- A single page. Its bytes live in content_blob (by sha, the raw .md incl. front matter);
-- the search columns are the DERIVED, indexable projection of that page:
--   nrm_search_data : the page's readable PROSE — markdown/directive/code chrome stripped
--                     (internal.markdown_to_search_text), lowercased + accent-folded.
--   nrm_keywords    : front-matter search metadata (description / summary / keywords),
--                     same normalization — the author's hand-picked terms.
-- search_vector weights them so a title hit outranks a keyword hit outranks a body hit
-- (A > B > C); ts_rank reads those weights. Both nrm_* columns feed the trigram fallback.
create table if not exists public.document (
    created_at timestamp with time zone default now()           not null,
    created_by text                     default 'unknown'::text not null,
    updated_at timestamp with time zone default now()           not null,
    updated_by text                     default 'unknown'::text not null,
    document_id     bigint  generated always as identity primary key,
    doc_variant_id  integer not null references public.doc_variant,
    slug            text    not null,
    title           text,
    content_sha     text    not null references public.content_blob,
    frontmatter     jsonb   default '{}'::jsonb not null,
    nrm_search_data text,
    nrm_keywords    text,
    search_vector   tsvector generated always as (
        setweight(to_tsvector('simple', coalesce(title, '')),           'A') ||
        setweight(to_tsvector('simple', coalesce(nrm_keywords, '')),    'B') ||
        setweight(to_tsvector('simple', coalesce(nrm_search_data, '')), 'C')
    ) stored
);

create unique index if not exists uq_document        on public.document (doc_variant_id, slug);
create index        if not exists ix_document_search on public.document using gin (search_vector);
create index        if not exists ix_trgm_document_search
    on public.document using gist (nrm_search_data ext.gist_trgm_ops);

-- ---------------------------------------------------------------------------
-- Functions
-- ---------------------------------------------------------------------------

-- internal.markdown_to_search_text — reduce a stored .md page to the readable prose we
-- want in the full-text index: drop everything that is *syntax*, not content, so a query
-- ranks on what the page says, not on `:::showcase`, fence flags or demo code.
--
-- Best-effort, deterministic, dependency-free (pure regex) so the ingestion boundary can
-- derive it without the Elixir engine — the future publish CLI may instead pass the
-- engine's own node-tree extraction via ensure_document(_search_text := …), which wins.
-- Steps, in order: strip leading front matter · `:::code`/`:::demo`/`:::run` blocks (their
-- bodies are source, not prose) · fenced code (``` and ~~~) · remaining `:::`
-- directive lines · angle brackets · table pipes · [label](url) → label · residual md markers
-- (`# * _ > ~ [ ]`) · separator/rule dash-runs · collapse whitespace. Caller lowercases
-- and accent-folds the result.
create or replace function internal.markdown_to_search_text(_md text)
returns text
language sql
immutable
as $$
    select regexp_replace(
           regexp_replace(
           regexp_replace(
           regexp_replace(
           regexp_replace(
           regexp_replace(
           regexp_replace(
           regexp_replace(
           regexp_replace(
           regexp_replace(
           regexp_replace(coalesce(_md, ''), '\A---\s*\n.*?\n---\s*\n', ' ', ''),
                               ':::(?:code|demo|run)[^\n]*\n.*?\n[ \t]*:::[ \t]*(\n|$)', ' ', 'g'), -- code/demo/run blocks
                               '`{3,}[^\n]*\n.*?`{3,}', ' ', 'g'),   -- ``` fences
                               '~{3,}[^\n]*\n.*?~{3,}', ' ', 'g'),   -- ~~~ fences
                               '^\s*:::.*$',            ' ', 'gn'),  -- remaining directive lines
                               '[<>]',                  ' ', 'g'),   -- angle brackets only
                                                                     -- (keep `<web-multiselect>` as a token)
                               '[|]',                   ' ', 'g'),   -- table pipes
                               '\[([^\]]*)\]\([^)]*\)', '\1', 'g'),  -- links -> label
                               '[`#*_>~\[\]]',          ' ', 'g'),   -- md markers
                               '-{2,}',                 ' ', 'g'),   -- --- separators/hr
                               '\s+',                   ' ', 'g');   -- collapse whitespace
$$;

-- internal.document_keywords — normalized front-matter search metadata. `keywords` may be
-- a JSON array (["forms","validation"]) or a plain string; description/summary are folded
-- in so an author's abstract is searchable even when its words never appear in the body.
create or replace function internal.document_keywords(_frontmatter jsonb)
returns text
language sql
immutable
as $$
    select nullif(lower(ext.unaccent(trim(concat_ws(' ',
        _frontmatter->>'description',
        _frontmatter->>'summary',
        case jsonb_typeof(_frontmatter->'keywords')
            when 'array'  then (select string_agg(kw, ' ')
                                from jsonb_array_elements_text(_frontmatter->'keywords') kw)
            when 'string' then _frontmatter->>'keywords'
            else ''
        end
    )))), '');
$$;

-- public.ensure_doc_set — idempotent upsert of a doc set by code. _kind_code null =
-- "leave kind alone" (new sets default to 'component'; existing keep theirs) so
-- re-publishing a page never clobbers a deliberate kind.
create or replace function public.ensure_doc_set(
    _created_by text,
    _correlation_id text,
    _code text,
    _title text default null,
    _kind_code text default null,
    _tenant_id integer default 1
)
returns table(__doc_set_id integer, __code text, __kind_code text, __title text)
rows 1
language plpgsql
as $$
begin
    return query
        insert into public.doc_set as s (code, kind_code, title, created_by, updated_by)
        values (_code, coalesce(_kind_code, 'component'), _title, _created_by, _created_by)
        on conflict (code) do update
            set kind_code  = coalesce(_kind_code, s.kind_code),
                title      = coalesce(_title, s.title),
                updated_by = _created_by,
                updated_at = now()
        returning s.doc_set_id, s.code, s.kind_code, s.title;
end;
$$;

-- public.ensure_doc_set_package — attach (or update) a registry identity to a set,
-- creating the set if needed.
create or replace function public.ensure_doc_set_package(
    _created_by text,
    _correlation_id text,
    _doc_set_code text,
    _ecosystem_code text,
    _package_name text,
    _is_primary boolean default false,
    _tenant_id integer default 1
)
returns table(__doc_set_package_id integer, __doc_set_id integer, __ecosystem_code text, __package_name text)
rows 1
language plpgsql
as $$
declare
    ___doc_set_id integer;
begin
    select eds.__doc_set_id into ___doc_set_id
    from public.ensure_doc_set(_created_by, _correlation_id, _doc_set_code, null, null, _tenant_id) eds;

    return query
        insert into public.doc_set_package as sp
            (doc_set_id, ecosystem_code, package_name, is_primary, created_by, updated_by)
        values (___doc_set_id, _ecosystem_code, _package_name, coalesce(_is_primary, false), _created_by, _created_by)
        on conflict (ecosystem_code, package_name) do update
            set is_primary = coalesce(_is_primary, sp.is_primary),
                updated_by = _created_by,
                updated_at = now()
        returning sp.doc_set_package_id, sp.doc_set_id, sp.ecosystem_code, sp.package_name;
end;
$$;

-- public.ensure_doc_variant — idempotent upsert of a (set, variant), creating the set
-- if needed. All optional attrs are null-means-leave-alone on update.
create or replace function public.ensure_doc_variant(
    _created_by text,
    _correlation_id text,
    _doc_set_code text,
    _code text,
    _title text default null,
    _is_default boolean default null,
    _show_in_path boolean default null,
    _sort_order integer default null,
    _maturity_code text default null,
    _applies_to jsonb default null,
    _content_sha text default null,
    _tenant_id integer default 1
)
returns table(__doc_variant_id integer, __doc_set_id integer, __code text)
rows 1
language plpgsql
as $$
declare
    ___doc_set_id integer;
begin
    select eds.__doc_set_id into ___doc_set_id
    from public.ensure_doc_set(_created_by, _correlation_id, _doc_set_code, null, null, _tenant_id) eds;

    return query
        insert into public.doc_variant as v
            (doc_set_id, code, title, is_default, show_in_path, sort_order,
             maturity_code, applies_to, content_sha, created_by, updated_by)
        values
            (___doc_set_id, _code, _title, coalesce(_is_default, false), coalesce(_show_in_path, true),
             coalesce(_sort_order, 0), _maturity_code, _applies_to, _content_sha, _created_by, _created_by)
        on conflict (doc_set_id, code) do update
            set title         = coalesce(_title, v.title),
                is_default    = coalesce(_is_default, v.is_default),
                show_in_path  = coalesce(_show_in_path, v.show_in_path),
                sort_order    = coalesce(_sort_order, v.sort_order),
                maturity_code = coalesce(_maturity_code, v.maturity_code),
                applies_to    = coalesce(_applies_to, v.applies_to),
                content_sha   = coalesce(_content_sha, v.content_sha),
                updated_by    = _created_by,
                updated_at    = now()
        returning v.doc_variant_id, v.doc_set_id, v.code;
end;
$$;

-- public.ensure_content_blob — content-addressed insert. __deduped = true when the bytes
-- were already present (nothing written) — the P4 dedup, in SQL.
create or replace function public.ensure_content_blob(
    _created_by text,
    _sha text,
    _content bytea,
    _byte_size bigint
)
returns table(__sha text, __deduped boolean)
rows 1
language plpgsql
as $$
declare
    __rows integer;
begin
    insert into public.content_blob (sha, byte_size, content, created_by)
    values (_sha, _byte_size, _content, _created_by)
    on conflict (sha) do nothing;

    get diagnostics __rows = row_count;
    return query select _sha, (__rows = 0);
end;
$$;

-- public.ensure_document — publish one page into a variant: dedup its bytes into a blob,
-- ensure the set + variant, then upsert the document with its derived search projection.
-- The stored blob is the raw .md (front matter + body); the index is built from the
-- readable prose (internal.markdown_to_search_text) + the front-matter keywords, NOT the
-- markdown syntax. `_search_text` lets a smarter caller (the engine's node-tree
-- extraction) override the SQL prose stripper; null = derive it here.
create or replace function public.ensure_document(
    _created_by text,
    _correlation_id text,
    _doc_set_code text,
    _variant_code text,
    _slug text,
    _title text,
    _content text,
    _frontmatter jsonb   default '{}'::jsonb,
    _content_sha text    default null,
    _search_text text    default null,
    _tenant_id integer   default 1
)
returns table(__document_id bigint, __content_sha text, __deduped boolean)
rows 1
language plpgsql
as $$
declare
    ___doc_variant_id integer;
    __bytes           bytea   := convert_to(_content, 'UTF8');
    __sha             text;
    __deduped         boolean;
    __frontmatter     jsonb   := coalesce(_frontmatter, '{}'::jsonb);
    __nrm             text    := lower(ext.unaccent(
                                     coalesce(_search_text, internal.markdown_to_search_text(_content))));
    __keywords        text    := internal.document_keywords(__frontmatter);
begin
    __sha := coalesce(_content_sha, 'sha256:' || encode(sha256(__bytes), 'hex'));

    select ecb.__deduped into __deduped
    from public.ensure_content_blob(_created_by, __sha, __bytes, octet_length(__bytes)) ecb;

    select edv.__doc_variant_id into ___doc_variant_id
    from public.ensure_doc_variant(_created_by, _correlation_id, _doc_set_code, _variant_code,
                                   null, null, null, null, null, null, null, _tenant_id) edv;

    return query
        insert into public.document as d
            (doc_variant_id, slug, title, content_sha, frontmatter,
             nrm_search_data, nrm_keywords, created_by, updated_by)
        values
            (___doc_variant_id, _slug, _title, __sha, __frontmatter,
             __nrm, __keywords, _created_by, _created_by)
        on conflict (doc_variant_id, slug) do update
            set title           = excluded.title,
                content_sha     = excluded.content_sha,
                frontmatter     = excluded.frontmatter,
                nrm_search_data = excluded.nrm_search_data,
                nrm_keywords    = excluded.nrm_keywords,
                updated_by      = _created_by,
                updated_at      = now()
        returning d.document_id, __sha, __deduped;
end;
$$;

-- public.list_doc_sets — every documented subject with its primary package identity.
create or replace function public.list_doc_sets()
returns table(__code text, __kind_code text, __title text, __ecosystem_code text, __package_name text)
language sql
stable
as $$
    select s.code, s.kind_code, s.title, sp.ecosystem_code, sp.package_name
    from public.doc_set s
        left join lateral (
            select p.ecosystem_code, p.package_name
            from public.doc_set_package p
            where p.doc_set_id = s.doc_set_id
            order by p.is_primary desc, p.doc_set_package_id
            limit 1
        ) sp on true
    order by s.code;
$$;

-- public.list_doc_variants — a set's variants, most prominent first. show_in_path tells
-- the renderer whether to include the variant as a URL segment.
create or replace function public.list_doc_variants(_doc_set_code text)
returns table(
    __code text, __title text, __is_default boolean,
    __show_in_path boolean, __maturity_code text, __applies_to jsonb
)
language sql
stable
as $$
    select v.code, v.title, v.is_default, v.show_in_path, v.maturity_code, v.applies_to
    from public.doc_variant v
        inner join public.doc_set s on s.doc_set_id = v.doc_set_id
    where s.code = _doc_set_code
    order by v.sort_order desc, v.code;
$$;

-- public.get_default_variant — the landing variant for a set (is_default, else highest
-- sort_order).
create or replace function public.get_default_variant(_doc_set_code text)
returns table(__code text, __title text, __show_in_path boolean)
rows 1
language sql
stable
as $$
    select v.code, v.title, v.show_in_path
    from public.doc_variant v
        inner join public.doc_set s on s.doc_set_id = v.doc_set_id
    where s.code = _doc_set_code
    order by v.is_default desc, v.sort_order desc, v.code
    limit 1;
$$;

-- public.get_document — fetch a page's rendered inputs (content as text + frontmatter).
-- Public content utility: no permission check.
create or replace function public.get_document(_doc_set_code text, _variant_code text, _slug text)
returns table(__slug text, __title text, __content text, __frontmatter jsonb)
rows 1
language plpgsql
stable
as $$
begin
    return query
        select d.slug, d.title, convert_from(b.content, 'UTF8'), d.frontmatter
        from public.document d
            inner join public.doc_variant v  on v.doc_variant_id = d.doc_variant_id
            inner join public.doc_set s      on s.doc_set_id = v.doc_set_id
            inner join public.content_blob b on b.sha = d.content_sha
        where s.code = _doc_set_code
          and v.code = _variant_code
          and d.slug = _slug;
end;
$$;

-- public.get_document_index — the DERIVED search projection of a page, for inspecting how
-- a document is indexed (the harness renders this next to the page). Returns the extracted
-- prose, the front-matter keywords, and the stored lexemes with their A/B/C weight labels.
create or replace function public.get_document_index(_doc_set_code text, _variant_code text, _slug text)
returns table(__title text, __keywords text, __search_text text, __lexemes text)
rows 1
language plpgsql
stable
as $$
begin
    return query
        select d.title, d.nrm_keywords, d.nrm_search_data, d.search_vector::text
        from public.document d
            inner join public.doc_variant v on v.doc_variant_id = d.doc_variant_id
            inner join public.doc_set s     on s.doc_set_id = v.doc_set_id
        where s.code = _doc_set_code
          and v.code = _variant_code
          and d.slug = _slug;
end;
$$;

-- public.resolve_doc_variant — given an installed package version, find the variant whose
-- declared applies_to covers it (half-open [from, to) semver bounds; pre-release suffix
-- ignored for containment). __matched = false = no coverage, fell back to the default.
create or replace function public.resolve_doc_variant(_doc_set_code text, _version text)
returns table(__code text, __title text, __show_in_path boolean, __matched boolean)
rows 1
language plpgsql
stable
as $$
declare
    __core int[] := string_to_array(split_part(_version, '-', 1), '.')::int[];
    __hit  record;
begin
    select v.code, v.title, v.show_in_path
    into __hit
    from public.doc_variant v
        inner join public.doc_set s on s.doc_set_id = v.doc_set_id
    where s.code = _doc_set_code
      and v.applies_to is not null
      and exists (
            select 1
            from jsonb_array_elements(v.applies_to) r
            where __core >= string_to_array(r->>'from', '.')::int[]
              and __core <  string_to_array(r->>'to',   '.')::int[]
          )
    order by v.sort_order desc
    limit 1;

    if found then
        return query select __hit.code, __hit.title, __hit.show_in_path, true;
    else
        return query select dv.__code, dv.__title, dv.__show_in_path, false
                     from public.get_default_variant(_doc_set_code) dv;
    end if;
end;
$$;

-- public.search_documents — full-text (tsvector, ranked) + trigram substring search.
--   _search_criteria : {"text": "...", "doc_set": "web-multiselect", "kind": "component"}  (WHAT)
--   _search_settings : {"page": 1, "page_size": 20,
--                       "order_by": "rank|title|slug", "order_dir": "desc|asc"}  (HOW)
-- Unknown keys ignored; missing keys defaulted; order_by is whitelisted (no dynamic
-- SQL). tsvector/tsquery stay internal — only stock types cross the boundary.
create or replace function public.search_documents(
    _correlation_id text,
    _search_criteria jsonb   default '{}'::jsonb,
    _search_settings jsonb   default '{}'::jsonb,
    _tenant_id integer       default 1
)
returns table(
    __doc_set_code text,
    __kind_code    text,
    __variant_code text,
    __slug         text,
    __title        text,
    __rank         real,
    __total_count  bigint
)
language plpgsql
stable
as $$
declare
    __text      text    := nullif(_search_criteria->>'text', '');
    __doc_set   text    := nullif(_search_criteria->>'doc_set', '');
    __kind      text    := nullif(_search_criteria->>'kind', '');
    __page      integer := greatest(coalesce((_search_settings->>'page')::int, 1), 1);
    __page_size integer := least(greatest(coalesce((_search_settings->>'page_size')::int, 20), 1), 200);
    __order_by  text    := coalesce(_search_settings->>'order_by', 'rank');
    __order_dir text    := case lower(coalesce(_search_settings->>'order_dir', 'desc'))
                                when 'asc' then 'asc' else 'desc' end;
    __query     tsquery := case when __text is null then null
                                else websearch_to_tsquery('simple', __text) end;
    __nrm       text    := case when __text is null then null
                                else lower(ext.unaccent(__text)) end;
begin
    return query
        with matched as (
            select
                s.code      as doc_set_code,
                s.kind_code as kind_code,
                v.code      as variant_code,
                d.slug      as slug,
                d.title     as title,
                case when __query is null then 0::real
                     else ts_rank(d.search_vector, __query) end as rank
            from public.document d
                inner join public.doc_variant v on v.doc_variant_id = d.doc_variant_id
                inner join public.doc_set s     on s.doc_set_id = v.doc_set_id
            where (__doc_set is null or s.code = __doc_set)
              and (__kind is null or s.kind_code = __kind)
              and (
                    __query is null
                    or d.search_vector @@ __query
                    or d.nrm_search_data like '%' || __nrm || '%'
                    or d.nrm_keywords like '%' || __nrm || '%'
                  )
        )
        select m.doc_set_code, m.kind_code, m.variant_code, m.slug, m.title, m.rank,
               count(*) over () as total_count
        from matched m
        order by
            case when __order_by = 'rank'  and __order_dir = 'desc' then m.rank  end desc nulls last,
            case when __order_by = 'rank'  and __order_dir = 'asc'  then m.rank  end asc  nulls last,
            case when __order_by = 'title' and __order_dir = 'desc' then m.title end desc,
            case when __order_by = 'title' and __order_dir = 'asc'  then m.title end asc,
            m.slug
        limit __page_size offset (__page - 1) * __page_size;
end;
$$;

select * from public.stop_version_update('1', _component := 'keen_docs');
