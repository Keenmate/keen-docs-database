set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Charlie has no initial access to Alpha
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 1: Charlie has no initial direct access to Alpha';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    -- Revoke any group access Charlie got in previous test file
    DELETE FROM auth.user_group_member
    WHERE user_id = __charlie_id
      AND user_group_id IN (SELECT user_group_id FROM auth.user_group WHERE code = 'projtest_alpha_readers');

    SELECT auth.has_resource_access(__charlie_id, 'share-1', 'project', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF NOT __has_access THEN
        RAISE NOTICE '  PASS: Charlie has no access to Alpha';
    ELSE
        RAISE EXCEPTION '  FAIL: Charlie should not have access yet';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Alice shares Alpha with Charlie (grants read on 'project' — cascades)
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __charlie_id bigint;
    __alpha_id bigint;
    __ra_id bigint;
    __flag text;
BEGIN
    RAISE NOTICE 'TEST 2: Alice shares Alpha with Charlie (read on project)';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT __resource_access_id, __access_flag
    FROM auth.grant_resource_access('test', __alice_id, 'share-2', 'project', __alpha_id,
        _target_user_id := __charlie_id, _access_flags := array['read'])
    INTO __ra_id, __flag;

    IF __ra_id IS NOT NULL AND __flag = 'read' THEN
        RAISE NOTICE '  PASS: Alice shared Alpha with Charlie (ra_id=%)', __ra_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Share failed, ra_id=%, flag=%', __ra_id, __flag;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Charlie can now read Alpha project
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __alpha_id bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 3: Charlie can now access Alpha after share';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT auth.has_resource_access(__charlie_id, 'share-3', 'project', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF __has_access THEN
        RAISE NOTICE '  PASS: Charlie now has read access to Alpha';
    ELSE
        RAISE EXCEPTION '  FAIL: Charlie should have access after share';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Charlie can read documents, invoices, contacts on Alpha (cascaded)
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __alpha_id bigint;
    __doc_count integer;
    __inv_count integer;
    __contact_count integer;
BEGIN
    RAISE NOTICE 'TEST 4: Charlie reads all sub-resources on Alpha after share';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT count(*) FROM public.get_project_documents('test', __charlie_id, 'share-4a', 1, __alpha_id)
    INTO __doc_count;

    SELECT count(*) FROM public.get_project_invoices('test', __charlie_id, 'share-4b', 1, __alpha_id)
    INTO __inv_count;

    SELECT count(*) FROM public.get_project_contacts('test', __charlie_id, 'share-4c', 1, __alpha_id)
    INTO __contact_count;

    IF __doc_count >= 1 AND __inv_count >= 1 AND __contact_count >= 1 THEN
        RAISE NOTICE '  PASS: Charlie sees % docs, % invoices, % contacts on Alpha',
            __doc_count, __inv_count, __contact_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 1 of each, got docs=%, inv=%, contacts=%',
            __doc_count, __inv_count, __contact_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Charlie cannot write to Alpha (only read was shared)
-- ============================================================================
DO $$
DECLARE
    __charlie_id bigint;
    __alpha_id bigint;
BEGIN
    RAISE NOTICE 'TEST 5: Charlie cannot create document in Alpha (no write ACL)';
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    BEGIN
        PERFORM public.create_project_document('test', __charlie_id, 'share-5', 1, __alpha_id, 'Should Fail.txt');
        RAISE EXCEPTION '  FAIL: Should have been denied but succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%no access%' OR SQLERRM LIKE '%35001%' THEN
            RAISE NOTICE '  PASS: Charlie correctly denied write (error=%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 6: Alice revokes Charlie's access to Alpha
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __charlie_id bigint;
    __alpha_id bigint;
    __deleted bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 6: Alice revokes Charlie access to Alpha';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    SELECT auth.revoke_resource_access('test', __alice_id, 'share-6', 'project', __alpha_id,
        _target_user_id := __charlie_id, _access_flags := array['read'])
    INTO __deleted;

    IF __deleted = 1 THEN
        RAISE NOTICE '  PASS: Revoked 1 grant';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 revoked, got %', __deleted;
    END IF;

    -- Verify Charlie lost access
    SELECT auth.has_resource_access(__charlie_id, 'share-6b', 'project', __alpha_id, 'read', 1, false)
    INTO __has_access;

    IF NOT __has_access THEN
        RAISE NOTICE '  PASS: Charlie no longer has access to Alpha';
    ELSE
        RAISE EXCEPTION '  FAIL: Charlie should no longer have access';
    END IF;
END $$;

-- ============================================================================
-- TEST 7: Alice grants multiple flags at once (read+write on project → cascades)
-- ============================================================================
DO $$
DECLARE
    __alice_id bigint;
    __charlie_id bigint;
    __alpha_id bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 7: Alice grants read+write to Charlie on Alpha';
    SELECT val FROM _projtest_data WHERE key = 'alice_id' INTO __alice_id;
    SELECT val FROM _projtest_data WHERE key = 'charlie_id' INTO __charlie_id;
    SELECT val FROM _projtest_data WHERE key = 'alpha_id' INTO __alpha_id;

    PERFORM auth.grant_resource_access('test', __alice_id, 'share-7', 'project', __alpha_id,
        _target_user_id := __charlie_id, _access_flags := array['read', 'write']);

    -- Verify both flags exist on project level
    SELECT count(*)
    FROM auth.get_resource_access_flags(__charlie_id, 'share-7b', 'project', __alpha_id) f
    WHERE f.__access_flag IN ('read', 'write')
    INTO __count;

    IF __count = 2 THEN
        RAISE NOTICE '  PASS: Charlie now has read+write on Alpha project';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 flags, got %', __count;
    END IF;
END $$;
