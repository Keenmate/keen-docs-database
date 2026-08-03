set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Group grant on project gives member read access to project
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 1: Bob has read access to Alpha via Editors group';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT auth.has_resource_access(__bob_id, 'grp-1', 'project', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF __has_access THEN
        RAISE NOTICE '  PASS: Bob has read access via group';
    ELSE
        RAISE EXCEPTION '  FAIL: Bob should have read access via Editors group';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Group grant on project gives write access to sub-types
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 2: Bob has write access to project.documents via group on project';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT auth.has_resource_access(__bob_id, 'grp-2', 'project.documents', __alpha_id, 'write', 1, false)
    INTO __has_access;

    IF __has_access THEN
        RAISE NOTICE '  PASS: Bob has write access to project.documents via group';
    ELSE
        RAISE EXCEPTION '  FAIL: Bob should have write access via group inheritance';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Group grant does NOT give delete access (only read+write granted)
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 3: Bob does NOT have delete on Alpha (group only has read+write)';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT auth.has_resource_access(__bob_id, 'grp-3', 'project', __alpha_id, 'delete', 1, false)
    INTO __has_access;

    IF NOT __has_access THEN
        RAISE NOTICE '  PASS: Bob correctly lacks delete access';
    ELSE
        RAISE EXCEPTION '  FAIL: Bob should NOT have delete access on Alpha';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: User deny on sub-type overrides group grant on parent
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 4: Bob deny on project.invoices overrides group grant on project';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT auth.has_resource_access(__bob_id, 'grp-4', 'project.invoices', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF NOT __has_access THEN
        RAISE NOTICE '  PASS: Deny on project.invoices correctly overrides group grant';
    ELSE
        RAISE EXCEPTION '  FAIL: Bob should be denied read on project.invoices';
    END IF;
END $$;

-- ============================================================================
-- TEST 5: New group member gets inherited access
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __alpha_id bigint;
    __new_group_id integer;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 5: New group grant propagates to member';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    -- Charlie has no direct access to Alpha
    SELECT auth.has_resource_access(__charlie_id, 'grp-5a', 'project', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF __has_access THEN
        RAISE EXCEPTION '  FAIL: Charlie should not yet have access to Alpha';
    END IF;

    -- Create a new group, add Charlie, grant read on Alpha
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_active, is_assignable)
    VALUES ('projtest', 'projtest', 1, 'Projtest Alpha Readers', 'projtest_alpha_readers', true, true)
    RETURNING user_group_id INTO __new_group_id;

    INSERT INTO auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    VALUES ('projtest', __new_group_id, __charlie_id, 'manual');

    PERFORM auth.grant_resource_access('projtest', 1, 'grp-5b', 'project', __alpha_id,
        _user_group_id := __new_group_id, _access_flags := array['read']);

    -- Now Charlie should have access to project and all sub-types
    SELECT auth.has_resource_access(__charlie_id, 'grp-5c', 'project', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF __has_access THEN
        RAISE NOTICE '  PASS: Charlie gained access to Alpha via new group';
    ELSE
        RAISE EXCEPTION '  FAIL: Charlie should have access via new group';
    END IF;
END $$;

-- ============================================================================
-- TEST 6: Effective flags show correct sources
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
    __flag_count integer;
    __flags text;
BEGIN
    RAISE NOTICE 'TEST 6: Bob effective flags on Alpha project show group source';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT count(*), string_agg(f.__access_flag || ':' || f.__source, ', ' order by f.__access_flag)
    FROM auth.get_resource_access_flags(__bob_id, 'grp-6', 'project', __alpha_id) f
    INTO __flag_count, __flags;

    IF __flag_count = 2 THEN
        RAISE NOTICE '  PASS: Bob has % flags on Alpha project (%)', __flag_count, __flags;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 flags (read, write), got % (%)', __flag_count, __flags;
    END IF;
END $$;
