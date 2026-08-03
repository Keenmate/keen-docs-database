set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Alice creates document in Alpha (write on project.documents via inheritance)
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __doc_id bigint;
    __title text;
BEGIN
    RAISE NOTICE 'TEST 1: Alice creates document in Alpha (write ACL inherited from project)';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT d.__document_id, d.__title
    FROM public.create_project_document('test', __alice_id, 'sub-1', 1, __alpha_id, 'New Test Doc.txt') d
    INTO __doc_id, __title;

    IF __doc_id IS NOT NULL AND __title = 'New Test Doc.txt' THEN
        RAISE NOTICE '  PASS: Document created (id=%, title=%)', __doc_id, __title;
        INSERT INTO _projtest_data VALUES ('new_doc_id', __doc_id)
        ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected document, got id=%, title=%', __doc_id, __title;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Bob creates document in Alpha (group grant on project → inherits to project.documents)
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
    __doc_id bigint;
BEGIN
    RAISE NOTICE 'TEST 2: Bob creates document in Alpha (group write inherited to project.documents)';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT d.__document_id
    FROM public.create_project_document('test', __bob_id, 'sub-2', 1, __alpha_id, 'Bob Test Doc.txt') d
    INTO __doc_id;

    IF __doc_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Bob created document via group ACL (id=%)', __doc_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Document creation returned null';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Charlie denied document in Alpha (no ACL on project or project.documents)
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __alpha_id bigint;
BEGIN
    RAISE NOTICE 'TEST 3: Charlie denied document creation in Alpha (no ACL)';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    BEGIN
        PERFORM public.create_project_document('test', __charlie_id, 'sub-3', 1, __alpha_id, 'Denied.txt');
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
-- TEST 4: Alice creates invoice in Alpha
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __inv_id bigint;
BEGIN
    RAISE NOTICE 'TEST 4: Alice creates invoice in Alpha';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT i.__invoice_id
    FROM public.create_project_invoice('test', __alice_id, 'sub-4', 1, __alpha_id, 'TEST-INV-NEW', 1500.00) i
    INTO __inv_id;

    IF __inv_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Invoice created (id=%)', __inv_id;
        INSERT INTO _projtest_data VALUES ('new_inv_id', __inv_id)
        ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    ELSE
        RAISE EXCEPTION '  FAIL: Invoice creation returned null';
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Bob DENIED invoice in Alpha (explicit deny on project.invoices)
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
BEGIN
    RAISE NOTICE 'TEST 5: Bob denied invoice creation in Alpha (explicit deny on project.invoices)';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    BEGIN
        PERFORM public.create_project_invoice('test', __bob_id, 'sub-5', 1, __alpha_id, 'TEST-INV-DENIED', 999.00);
        RAISE EXCEPTION '  FAIL: Should have been denied but succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%no access%' OR SQLERRM LIKE '%35001%' THEN
            RAISE NOTICE '  PASS: Bob correctly denied on invoices (error=%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 6: Bob creates contact in Alpha (group grant on project → inherits to project.contacts)
-- ============================================================================
DO $$
DECLARE
    __bob_id bigint;
    __alpha_id bigint;
    __contact_id bigint;
BEGIN
    RAISE NOTICE 'TEST 6: Bob creates contact in Alpha (group write inherited to project.contacts)';
    SELECT val FROM _projtest_data WHERE key = 'bob_id' INTO __bob_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT c.__contact_id
    FROM public.create_project_contact('test', __bob_id, 'sub-6', 1, __alpha_id, 'Bob New Contact', 'new@test.com') c
    INTO __contact_id;

    IF __contact_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Bob created contact via group ACL (id=%)', __contact_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Contact creation returned null';
    END IF;
END $$;

-- ============================================================================
-- TEST 7: Alice gets documents in Alpha
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 7: Alice gets documents in Alpha';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT count(*) FROM public.get_project_documents('test', __alice_id, 'sub-7', 1, __alpha_id)
    INTO __count;

    -- 2 seed docs + 2 created in tests = at least 4
    IF __count >= 4 THEN
        RAISE NOTICE '  PASS: Alice sees % documents in Alpha', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 4 documents, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: Alice gets invoices in Alpha
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __alpha_id bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 8: Alice gets invoices in Alpha';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT count(*) FROM public.get_project_invoices('test', __alice_id, 'sub-8', 1, __alpha_id)
    INTO __count;

    -- 2 seed invoices + 1 created in test 4 = at least 3
    IF __count >= 3 THEN
        RAISE NOTICE '  PASS: Alice sees % invoices in Alpha', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 3 invoices, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: Dave (no RBAC) cannot get documents
-- ============================================================================
DO $$
DECLARE
    __dave_id bigint;
    __alpha_id bigint;
BEGIN
    RAISE NOTICE 'TEST 9: Dave denied by RBAC (no project permissions)';
    SELECT val FROM _projtest_data WHERE key = 'dave_id' INTO __dave_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    BEGIN
        PERFORM public.get_project_documents('test', __dave_id, 'sub-9', 1, __alpha_id);
        RAISE EXCEPTION '  FAIL: Should have been denied but succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%no_permission%' OR SQLERRM LIKE '%52001%' OR SQLERRM LIKE '%Unauthorized%' THEN
            RAISE NOTICE '  PASS: Dave correctly denied by RBAC (error=%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;
