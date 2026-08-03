set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Grant on project cascades to project.documents (read)
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 1: Grant on project cascades to project.documents (read)';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    -- Alice has read on 'project' for Alpha → should cascade to 'project.documents'
    SELECT auth.has_resource_access(__alice_id, 'hier-1', 'project.documents', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF __has_access THEN
        RAISE NOTICE '  PASS: project.documents read inherited from project grant';
    ELSE
        RAISE EXCEPTION '  FAIL: project.documents read should be inherited from project grant';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Grant on project cascades to project.invoices (write)
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 2: Grant on project cascades to project.invoices (write)';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    -- Alice has write on 'project' for Alpha → should cascade to 'project.invoices'
    SELECT auth.has_resource_access(__alice_id, 'hier-2', 'project.invoices', __alpha_id, 'write', 1, false)
    INTO __has_access;

    IF __has_access THEN
        RAISE NOTICE '  PASS: project.invoices write inherited from project grant';
    ELSE
        RAISE EXCEPTION '  FAIL: project.invoices write should be inherited from project grant';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Grant on project cascades to project.contacts (read)
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 3: Grant on project cascades to project.contacts (read)';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT auth.has_resource_access(__alice_id, 'hier-3', 'project.contacts', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF __has_access THEN
        RAISE NOTICE '  PASS: project.contacts read inherited from project grant';
    ELSE
        RAISE EXCEPTION '  FAIL: project.contacts read should be inherited from project grant';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Sub-type deny blocks only that sub-type (Bob: invoices denied, docs OK)
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
    __can_read_docs boolean;
    __can_read_invoices boolean;
    __can_read_contacts boolean;
BEGIN
    RAISE NOTICE 'TEST 4: Sub-type deny blocks only project.invoices for Bob';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT auth.has_resource_access(__bob_id, 'hier-4a', 'project.documents', __alpha_id, 'read', 1, false)
    INTO __can_read_docs;

    SELECT auth.has_resource_access(__bob_id, 'hier-4b', 'project.invoices', __alpha_id, 'read', 1, false)
    INTO __can_read_invoices;

    SELECT auth.has_resource_access(__bob_id, 'hier-4c', 'project.contacts', __alpha_id, 'read', 1, false)
    INTO __can_read_contacts;

    IF __can_read_docs AND NOT __can_read_invoices AND __can_read_contacts THEN
        RAISE NOTICE '  PASS: docs=%, invoices=%, contacts=% — deny only blocks invoices',
            __can_read_docs, __can_read_invoices, __can_read_contacts;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected docs=true, invoices=false, contacts=true, got docs=%, invoices=%, contacts=%',
            __can_read_docs, __can_read_invoices, __can_read_contacts;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Charlie with project read on Beta can access all sub-types
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __beta_id bigint;
    __can_read_project boolean;
    __can_read_docs boolean;
    __can_read_invoices boolean;
    __can_read_contacts boolean;
BEGIN
    RAISE NOTICE 'TEST 5: Charlie project read on Beta cascades to all sub-types';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'beta_id' INTO __beta_id;

    SELECT auth.has_resource_access(__charlie_id, 'hier-5a', 'project', __beta_id, 'read', 1, false)
    INTO __can_read_project;

    SELECT auth.has_resource_access(__charlie_id, 'hier-5b', 'project.documents', __beta_id, 'read', 1, false)
    INTO __can_read_docs;

    SELECT auth.has_resource_access(__charlie_id, 'hier-5c', 'project.invoices', __beta_id, 'read', 1, false)
    INTO __can_read_invoices;

    SELECT auth.has_resource_access(__charlie_id, 'hier-5d', 'project.contacts', __beta_id, 'read', 1, false)
    INTO __can_read_contacts;

    IF __can_read_project AND __can_read_docs AND __can_read_invoices AND __can_read_contacts THEN
        RAISE NOTICE '  PASS: All sub-types readable via project grant';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected all true, got project=%, docs=%, invoices=%, contacts=%',
            __can_read_project, __can_read_docs, __can_read_invoices, __can_read_contacts;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: Charlie cannot write to Beta (only read was granted)
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __beta_id bigint;
    __can_write boolean;
BEGIN
    RAISE NOTICE 'TEST 6: Charlie cannot write to Beta sub-types (read-only grant)';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'beta_id' INTO __beta_id;

    SELECT auth.has_resource_access(__charlie_id, 'hier-6', 'project.documents', __beta_id, 'write', 1, false)
    INTO __can_write;

    IF NOT __can_write THEN
        RAISE NOTICE '  PASS: Charlie correctly cannot write to project.documents on Beta';
    ELSE
        RAISE EXCEPTION '  FAIL: Charlie should not have write access';
    END IF;
END $$;

-- ============================================================================
-- TEST 7: get_project_access_matrix returns full grid
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __matrix_count integer;
    __types text;
BEGIN
    RAISE NOTICE 'TEST 7: get_project_access_matrix returns full sub-type x flag grid';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT count(*), string_agg(distinct m.__resource_type, ', ' order by m.__resource_type)
    FROM public.get_project_access_matrix('test', __alice_id, 'hier-7', 1, __alpha_id) m
    INTO __matrix_count, __types;

    -- Alice has read+write+delete+share on project → cascades to all 4 types × 4 flags = 16 rows
    IF __matrix_count >= 16 THEN
        RAISE NOTICE '  PASS: Matrix has % entries across types: %', __matrix_count, __types;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 16 matrix entries, got % (%)', __matrix_count, __types;
    END IF;
END $$;
