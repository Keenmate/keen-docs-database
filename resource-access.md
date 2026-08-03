# Resource Access (ACL) System

Resource-level access control layered on top of RBAC. While RBAC controls **what actions** a user can perform globally (e.g. "can create projects"), the ACL system controls **which specific resources** they can act on (e.g. "can read project #42").

---

## Tables

### `const.resource_type`

Registry of valid resource types. Global (not tenant-specific). Supports **hierarchical types** via ltree paths.

| Column | Type | Description |
|--------|------|-------------|
| `code` | text PK | Type identifier (e.g. `project`, `project.documents`) |
| `title` | text | Display name |
| `description` | text | Optional description |
| `is_active` | boolean | Whether type is active |
| `source` | text | Origin tracker (e.g. `projects_app`) |
| `parent_code` | text FK | Parent type reference (for validation) |
| `path` | ltree | Hierarchical path (auto-derived from code) |

### `const.resource_access_flag`

Registry of valid access flags. Extensible — add custom flags by inserting rows.

| Column | Type | Description |
|--------|------|-------------|
| `code` | text PK | Flag identifier |
| `title` | text | Display name |
| `source` | text | Origin tracker |

**Built-in flags:**

| Flag | Meaning |
|------|---------|
| `read` | View/read the resource |
| `write` | Create/modify the resource |
| `delete` | Delete the resource |
| `share` | Grant access to others |

Custom flags can be added (e.g. `export`, `comment`, `subscribe`). All flags work uniformly in grant/deny/check operations.

### `auth.resource_access`

Core ACL table. One row = one flag for one user or group on one resource. Partitioned by `root_type` (list partitioning) — all types sharing a root get the same partition (e.g. `project`, `project.documents`, `project.invoices` all use `auth.resource_access_project`).

| Column | Type | Description |
|--------|------|-------------|
| `resource_access_id` | bigint (identity) | PK (composite with root_type) |
| `tenant_id` | integer | Tenant FK (cascade delete) |
| `resource_type` | text | FK to `const.resource_type` |
| `root_type` | text | First segment of resource_type (for partitioning) |
| `resource_id` | bigint | Application-specific resource ID |
| `user_id` | bigint | Target user (NULL if group grant) |
| `user_group_id` | integer | Target group (NULL if user grant) |
| `access_flag` | text | FK to `const.resource_access_flag` |
| `is_deny` | boolean | `false` = grant, `true` = deny |
| `granted_by` | bigint | User who created this ACL entry |
| `created_at/by` | audit | Standard audit fields |
| `updated_at/by` | audit | Standard audit fields |

**Constraints:**
- Either `user_id` or `user_group_id` must be set (not both, not neither)
- Unique per `(resource_type, tenant_id, resource_id, user_id, access_flag)` for user grants
- Unique per `(resource_type, tenant_id, resource_id, user_group_id, access_flag)` for group grants

---

## Hierarchical Resource Types

Resource types can be organized into parent-child hierarchies using dot-separated codes and PostgreSQL's ltree extension.

### Registration

```sql
-- Root type — creates partition auth.resource_access_project
select * from auth.create_resource_type('app', 1, 'setup', 'project', 'Project',
    _description := 'Project root type', _source := 'projects_app');

-- Child types — share the 'project' partition (no new partitions)
select * from auth.create_resource_type('app', 1, 'setup', 'project.documents', 'Project Documents',
    _parent_code := 'project', _source := 'projects_app');
select * from auth.create_resource_type('app', 1, 'setup', 'project.invoices', 'Project Invoices',
    _parent_code := 'project', _source := 'projects_app');
select * from auth.create_resource_type('app', 1, 'setup', 'project.contacts', 'Project Contacts',
    _parent_code := 'project', _source := 'projects_app');
```

Result in `const.resource_type`:

| code | parent_code | path |
|------|-------------|------|
| `project` | NULL | `project` |
| `project.documents` | `project` | `project.documents` |
| `project.invoices` | `project` | `project.invoices` |
| `project.contacts` | `project` | `project.contacts` |

### Inheritance Model

**Grant on parent cascades to children:**
- Grant `read` on `project` for project #1 → user can also read `project.documents`, `project.invoices`, `project.contacts` for project #1
- Only one ACL row needed — the system walks up the hierarchy automatically

**Sub-type deny overrides parent grant:**
- Grant `read` on `project` + deny `read` on `project.invoices` → user can read docs and contacts but NOT invoices
- Deny is checked most-specific-first (deepest in hierarchy)

**No upward propagation:**
- Grant on `project.documents` does NOT grant access to `project` itself
- Children inherit from parents, not the other way around

### Walk-Up Algorithm

When checking `has_resource_access('project.documents', resource_id, 'read')`:

1. Check `project.documents` — deny found? → **blocked**
2. Check `project.documents` — grant found? → **allowed**
3. Walk up to `project` — deny found? → **blocked**
4. Walk up to `project` — grant found? → **allowed** (inherited)
5. No match → denied

### Key Design Principle

All sub-resources use the **project_id** as the `resource_id`, not the document/invoice/contact ID. Access is controlled at the project level, with sub-type granularity determining which aspects of the project the user can see.

```sql
-- ACL check for documents uses project_id, not document_id
perform auth.has_resource_access(_user_id, _corr, 'project.documents', _project_id, 'read');
```

---

## Access Check Algorithm

When `auth.has_resource_access()` is called, checks happen in this order:

1. **System user** (id=1) → always allowed
2. **Tenant owner** → always allowed
3. **Walk up hierarchy** (most specific first):
   - **User-level deny** (`is_deny=true`) → **blocked**, overrides everything
   - **User-level grant** (`is_deny=false`) → allowed
   - **Group-level grant** (via `user_group_member` + active group) → allowed
4. **No matching row** → denied

**Key rule:** User-level deny beats all group grants. This is how you create exceptions — even if Bob is in the "Editors" group with write on a project, a user-level deny on `project.invoices` blocks him from invoices specifically.

---

## Deny Model

- Denies are **user-level only** — you cannot deny a group
- Denies are **per-flag** — deny `read` doesn't affect `write`
- Denies are **explicit** — must be set with `auth.deny_resource_access()`
- Denies on a sub-type **only block that sub-type** — deny on `project.invoices` doesn't affect `project.documents`
- To remove a deny, use `auth.revoke_resource_access()` (deletes the deny row)

---

## Group Access

1. **Grant:** Call `auth.grant_resource_access()` with `_user_group_id` to grant flags to a group
2. **Membership resolution:** Access check joins `resource_access` → `user_group_member` → `user_group` (must be `is_active=true`)
3. **Effective flags:** `auth.get_resource_access_flags()` returns group grants with source = group title
4. **Hierarchy:** Group grant on `project` cascades to all sub-types for all group members
5. All group types (internal, external, hybrid) work equally with resource access

---

## Functions

### Checking Access

#### `auth.has_resource_access`

Check if user has a specific flag on a resource. Walks up the hierarchy for inherited access.

```sql
auth.has_resource_access(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _required_flag  text    default 'read',
    _tenant_id      integer default 1,
    _throw_err      boolean default true
) returns boolean
```

```sql
-- Throws if denied (default)
perform auth.has_resource_access(_user_id, _corr_id, 'project', _project_id, 'read', _tenant_id);

-- Check sub-type (inherits from project grant)
perform auth.has_resource_access(_user_id, _corr_id, 'project.documents', _project_id, 'read', _tenant_id);

-- Silent check
if auth.has_resource_access(_user_id, _corr_id, 'project.invoices', _project_id, 'write', _tenant_id, _throw_err := false) then
    -- user has write access to invoices
end if;
```

#### `auth.filter_accessible_resources`

Bulk filter — returns subset of resource IDs that user can access.

```sql
auth.filter_accessible_resources(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_ids   bigint[],
    _required_flag  text    default 'read',
    _tenant_id      integer default 1
) returns table(__resource_id bigint)
```

```sql
select p.project_id, p.title
from public.project p
inner join auth.filter_accessible_resources(
    _user_id, _corr_id, 'project',
    (select array_agg(project_id) from public.project where tenant_id = _tenant_id),
    'read', _tenant_id
) acl on acl.__resource_id = p.project_id;
```

#### `auth.get_resource_access_flags`

Returns all effective flags a user has on a resource, with their source.

```sql
auth.get_resource_access_flags(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _tenant_id      integer default 1
) returns table(__access_flag text, __source text)
```

Source values: `system` (system user), `owner` (tenant owner), `direct` (user-level grant), or group title (group-level grant).

#### `auth.get_resource_access_matrix`

Returns the full sub-type × flag matrix for a resource hierarchy. Shows what access a user has across all descendant types.

```sql
auth.get_resource_access_matrix(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,       -- root or parent type (e.g. 'project')
    _resource_id    bigint,
    _tenant_id      integer default 1
) returns table(
    __resource_type text,       -- all descendant types
    __access_flag   text,       -- all access flags
    __source        text        -- 'system', 'owner', 'direct', or group title
)
```

```sql
-- Get full access matrix for a project
select * from auth.get_resource_access_matrix(_user_id, _corr_id, 'project', _project_id);
-- Returns rows like:
--   project           | read  | direct
--   project           | write | direct
--   project.documents | read  | direct  (inherited from project grant)
--   project.documents | write | direct  (inherited from project grant)
--   project.invoices  | read  | direct  (inherited — unless denied)
--   project.contacts  | read  | Editors (inherited from group grant on project)
```

### Granting Access

#### `auth.grant_resource_access`

Grant flags to a user or group. Idempotent — re-granting is a no-op, granting over a deny flips it to a grant.

```sql
auth.grant_resource_access(
    _created_by     text,
    _user_id        bigint,          -- caller (must have resources.grant_access)
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _target_user_id bigint  default null,
    _user_group_id  integer default null,
    _access_flags   text[]  default array['read'],
    _tenant_id      integer default 1
) returns table(__resource_access_id bigint, __access_flag text)
```

```sql
-- Grant at project level — cascades to all sub-types
perform auth.grant_resource_access('app', _admin_id, _corr_id, 'project', _project_id,
    _target_user_id := _user_id, _access_flags := array['read','write']);

-- Grant at sub-type level only (does NOT cascade upward)
perform auth.grant_resource_access('app', _admin_id, _corr_id, 'project.documents', _project_id,
    _target_user_id := _user_id, _access_flags := array['read']);

-- Grant to group — cascades to all sub-types for all members
perform auth.grant_resource_access('app', _admin_id, _corr_id, 'project', _project_id,
    _user_group_id := _group_id, _access_flags := array['read','write']);
```

### Denying Access

#### `auth.deny_resource_access`

Explicit deny — user-level only. Overrides all group grants for that user on the specified type.

```sql
auth.deny_resource_access(
    _created_by     text,
    _user_id        bigint,          -- caller (must have resources.deny_access)
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _target_user_id bigint,          -- required (no group denies)
    _access_flags   text[]  default array['read'],
    _tenant_id      integer default 1
) returns table(__resource_access_id bigint, __access_flag text)
```

```sql
-- Deny invoices only — docs and contacts remain accessible
perform auth.deny_resource_access('app', _admin_id, _corr_id, 'project.invoices', _project_id,
    _target_user_id := _user_id, _access_flags := array['read','write']);
```

### Revoking Access

#### `auth.revoke_resource_access`

Revoke specific flags (or all flags if `_access_flags` is NULL).

```sql
auth.revoke_resource_access(
    _deleted_by     text,
    _user_id        bigint,          -- caller (must have resources.revoke_access)
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _target_user_id bigint  default null,
    _user_group_id  integer default null,
    _access_flags   text[]  default null,   -- NULL = revoke all
    _tenant_id      integer default 1
) returns bigint                             -- count of deleted rows
```

```sql
-- Revoke specific flags
select auth.revoke_resource_access('app', _admin_id, _corr_id, 'project', _project_id,
    _target_user_id := _user_id, _access_flags := array['write']);

-- Revoke all flags
select auth.revoke_resource_access('app', _admin_id, _corr_id, 'project', _project_id,
    _target_user_id := _user_id);
```

#### `auth.revoke_all_resource_access`

Remove ALL ACL rows for a resource (all users, all groups, all flags). Used when deleting resources.

```sql
auth.revoke_all_resource_access(
    _deleted_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _tenant_id      integer default 1
) returns bigint
```

### Querying Grants

#### `auth.get_resource_grants`

List all grants and denies on a resource.

```sql
auth.get_resource_grants(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _tenant_id      integer default 1
) returns table(
    __resource_access_id bigint,
    __user_id            bigint,
    __user_display_name  text,
    __user_group_id      integer,
    __group_title        text,
    __access_flag        text,
    __is_deny            boolean,
    __granted_by         bigint,
    __granted_by_name    text,
    __created_at         timestamptz
)
```

#### `auth.get_user_accessible_resources`

List all resources a user can access with a given flag.

```sql
auth.get_user_accessible_resources(
    _user_id         bigint,          -- caller
    _correlation_id  text,
    _target_user_id  bigint,          -- whose resources to query
    _resource_type   text,
    _access_flag     text    default 'read',
    _tenant_id       integer default 1
) returns table(
    __resource_id  bigint,
    __access_flags text[],
    __source       text
)
```

---

## Registering New Resource Types

### Flat (non-hierarchical)

```sql
-- Register the type (creates partition automatically)
select * from auth.create_resource_type('app', 1, 'setup', 'report', 'Reports');

-- Grant/check access
perform auth.grant_resource_access('app', _admin_id, _corr_id, 'report', _report_id,
    _target_user_id := _user_id, _access_flags := array['read','write']);
```

### Hierarchical

```sql
-- Root type (creates partition)
select * from auth.create_resource_type('app', 1, 'setup', 'project', 'Project',
    _description := 'CRM project', _source := 'my_app');

-- Child types (share root partition)
select * from auth.create_resource_type('app', 1, 'setup', 'project.documents', 'Documents',
    _parent_code := 'project', _source := 'my_app');
select * from auth.create_resource_type('app', 1, 'setup', 'project.invoices', 'Invoices',
    _parent_code := 'project', _source := 'my_app');

-- Grant at root level → cascades to all children
perform auth.grant_resource_access('app', _admin_id, _corr_id, 'project', _project_id,
    _target_user_id := _user_id, _access_flags := array['read','write']);

-- Deny specific child type → blocks only that sub-type
perform auth.deny_resource_access('app', _admin_id, _corr_id, 'project.invoices', _project_id,
    _target_user_id := _user_id, _access_flags := array['read']);
```

---

## Integration Pattern (RBAC + ACL)

Every application function follows the dual-check pattern:

```sql
create or replace function public.get_project(
    _created_by text, _user_id bigint, _correlation_id text,
    _tenant_id integer, _project_id bigint
) returns table(...) as $$
begin
    -- 1. RBAC: Can user perform this action at all?
    perform auth.has_permission(_user_id, _correlation_id, 'projects.read_projects', _tenant_id);

    -- 2. ACL: Can user access THIS specific resource?
    perform auth.has_resource_access(_user_id, _correlation_id, 'project', _project_id, 'read', _tenant_id);

    -- 3. Do the work
    return query select ... from public.project where project_id = _project_id;
end;
$$ language plpgsql;
```

For sub-resources, ACL checks use the sub-type but the **project_id** as resource_id:

```sql
create or replace function public.get_project_documents(
    _created_by text, _user_id bigint, _correlation_id text,
    _tenant_id integer, _project_id bigint
) returns table(...) as $$
begin
    -- RBAC check
    perform auth.has_permission(_user_id, _correlation_id, 'projects.read_documents', _tenant_id);

    -- ACL check on sub-type (resource_id = project_id, not document_id)
    perform auth.has_resource_access(_user_id, _correlation_id, 'project.documents', _project_id,
        'read', _tenant_id);

    -- Return documents for this project
    return query select ... from public.project_document where project_id = _project_id;
end;
$$ language plpgsql;
```

For bulk queries, use `filter_accessible_resources`:

```sql
create or replace function public.get_projects(
    _created_by text, _user_id bigint, _correlation_id text,
    _tenant_id integer
) returns table(...) as $$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'projects.read_projects', _tenant_id);

    return query
    select p.*
    from public.project p
    inner join auth.filter_accessible_resources(
        _user_id, _correlation_id, 'project',
        (select array_agg(project_id) from public.project where tenant_id = _tenant_id),
        'read', _tenant_id
    ) acl on acl.__resource_id = p.project_id;
end;
$$ language plpgsql;
```

---

## RBAC Permissions Required

Functions in the `auth` schema require these RBAC permissions:

| Permission | Required by |
|------------|-------------|
| `resources.grant_access` | `auth.grant_resource_access()` |
| `resources.deny_access` | `auth.deny_resource_access()` |
| `resources.revoke_access` | `auth.revoke_resource_access()`, `auth.revoke_all_resource_access()` |
| `resources.get_grants` | `auth.get_resource_grants()`, `auth.get_user_accessible_resources()` |
| `resources.create_resource_type` | `auth.create_resource_type()` |

---

## Error Codes

| Code | Meaning |
|------|---------|
| 35001 | User has no access to resource (or explicitly denied) |
| 35002 | Neither user_id nor user_group_id provided in grant/revoke |
| 35003 | Resource type doesn't exist or is inactive |
| 35004 | Access flag doesn't exist |

## Journal Event Codes

| Code | Event | Function |
|------|-------|----------|
| 18001 | resource_type_created | `auth.create_resource_type()` |
| 18010 | resource_access_granted | `auth.grant_resource_access()` |
| 18011 | resource_access_revoked | `auth.revoke_resource_access()` |
| 18012 | resource_access_denied | `auth.deny_resource_access()` |
| 18013 | resource_access_bulk_revoked | `auth.revoke_all_resource_access()` |

---

## Partitioning

The `auth.resource_access` table is list-partitioned by `root_type`. All types sharing a root type use the same partition:

```
auth.resource_access (parent)
├── auth.resource_access_project   (root_type = 'project')
│   ├── resource_type = 'project'
│   ├── resource_type = 'project.documents'
│   ├── resource_type = 'project.invoices'
│   └── resource_type = 'project.contacts'
└── auth.resource_access_default   (catches unregistered types)
```

Only the root type creates a new partition. Child types share the parent's partition automatically. PostgreSQL prunes partitions automatically — queries filtered by `root_type` only scan the relevant partition.

---

## Projects App Example

The projects app in this repository demonstrates the full hierarchical system:

- **Resource types:** `project` (root), `project.documents`, `project.invoices`, `project.contacts` — all sharing one partition
- **RBAC permissions:** `projects.create_project`, `projects.read_projects`, `projects.update_project`, `projects.delete_project`, `projects.manage_documents`, `projects.read_documents`, `projects.manage_invoices`, `projects.read_invoices`, `projects.manage_contacts`, `projects.read_contacts`
- **Permission set:** "Project user" bundles all project + resource permissions
- **Users:** Alice (admin + project_user), Bob (project_user, Project Editors group member), Charlie (project_user), Dave (no permissions)
- **ACL grants:** Alice = full access on both projects (at `project` level), Editors group = read+write on Alpha (cascades to all sub-types), Charlie = read on Beta
- **Sub-type deny:** Bob is denied `read+write` on `project.invoices` for Alpha — he can see documents and contacts via the group grant on `project`, but invoices are blocked
- **Access matrix:** `get_project_access_matrix` returns the complete sub-type × flag grid showing inherited and denied access
- **Tests** covering project CRUD, sub-resource CRUD, hierarchy inheritance, group access, share workflow, and cleanup
