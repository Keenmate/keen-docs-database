set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Alice creates a project (has RBAC + auto-ACL)
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __project_id bigint;
    __title text;
BEGIN
    RAISE NOTICE 'TEST 1: Alice creates a project';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;

    SELECT p.__project_id, p.__title
    FROM public.create_project('test', __alice_id, 'test-1', 1, 'New Test Project') p
    INTO __project_id, __title;

    IF __project_id IS NOT NULL AND __title = 'New Test Project' THEN
        RAISE NOTICE '  PASS: Project created (id=%)', __project_id;
        INSERT INTO _projtest_data VALUES ('new_project_id', __project_id)
        ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected project creation, got id=%, title=%', __project_id, __title;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Dave (no RBAC) cannot create any project
-- ============================================================================
DO $$
DECLARE
    __dave_id bigint;
BEGIN
    RAISE NOTICE 'TEST 2: Dave denied project creation (no RBAC permission)';
    SELECT val FROM _projtest_data WHERE key = 'dave_id' INTO __dave_id;

    BEGIN
        PERFORM public.create_project('test', __dave_id, 'test-2', 1, 'Should Fail');
        RAISE EXCEPTION '  FAIL: Should have been denied but succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%no_permission%' OR SQLERRM LIKE '%52001%' OR SQLERRM LIKE '%Unauthorized%' THEN
            RAISE NOTICE '  PASS: Dave correctly denied by RBAC (error=%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 3: Alice sees all projects she has ACL on via get_projects
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 3: Alice sees all projects via get_projects';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;

    SELECT count(*) FROM public.get_projects('test', __alice_id, 'test-3', 1)
    INTO __count;

    -- Alice has ACL on Alpha, Beta, plus New Test Project from TEST 1
    IF __count >= 3 THEN
        RAISE NOTICE '  PASS: Alice sees % projects', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 3 projects, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Charlie sees only Project Beta (only ACL grant)
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __count integer;
    __found_title text;
BEGIN
    RAISE NOTICE 'TEST 4: Charlie sees only projects with read ACL';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;

    SELECT count(*), string_agg(p.__title, ', ')
    FROM public.get_projects('test', __charlie_id, 'test-4', 1) p
    INTO __count, __found_title;

    IF __count = 1 AND __found_title LIKE '%Beta%' THEN
        RAISE NOTICE '  PASS: Charlie sees % project(s): %', __count, __found_title;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 project (Beta), got % (%)', __count, __found_title;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Bob sees only Project Alpha (via group grant)
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __count integer;
    __found_title text;
BEGIN
    RAISE NOTICE 'TEST 5: Bob sees only projects via group ACL';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;

    SELECT count(*), string_agg(p.__title, ', ')
    FROM public.get_projects('test', __bob_id, 'test-5', 1) p
    INTO __count, __found_title;

    IF __count = 1 AND __found_title LIKE '%Alpha%' THEN
        RAISE NOTICE '  PASS: Bob sees % project(s): %', __count, __found_title;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 project (Alpha), got % (%)', __count, __found_title;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: get_project works for Alice on a specific project
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __title text;
BEGIN
    RAISE NOTICE 'TEST 6: Alice can get_project on Alpha';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT p.__title FROM public.get_project('test', __alice_id, 'test-6', 1, __alpha_id) p
    INTO __title;

    IF __title = 'Test Project Alpha' THEN
        RAISE NOTICE '  PASS: Got project title=%', __title;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected "Test Project Alpha", got "%"', __title;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: Charlie denied get_project on Alpha (no ACL)
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __alpha_id bigint;
BEGIN
    RAISE NOTICE 'TEST 7: Charlie denied get_project on Alpha (no ACL)';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    BEGIN
        PERFORM public.get_project('test', __charlie_id, 'test-7', 1, __alpha_id);
        RAISE EXCEPTION '  FAIL: Should have been denied but succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%no access%' OR SQLERRM LIKE '%35001%' THEN
            RAISE NOTICE '  PASS: Charlie correctly denied (error=%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 8: Alice deletes a project she has delete ACL on
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __new_project_id bigint;
    __deleted bigint;
    __remaining integer;
BEGIN
    RAISE NOTICE 'TEST 8: Alice deletes a project (has delete ACL)';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'new_project_id' INTO __new_project_id;

    SELECT public.delete_project('test', __alice_id, 'test-8', 1, __new_project_id)
    INTO __deleted;

    SELECT count(*) FROM public.project WHERE project_id = __new_project_id INTO __remaining;

    IF __deleted = __new_project_id AND __remaining = 0 THEN
        RAISE NOTICE '  PASS: Project deleted (id=%)', __deleted;
    ELSE
        RAISE EXCEPTION '  FAIL: Deletion failed (deleted=%, remaining=%)', __deleted, __remaining;
    END IF;
END $$;
