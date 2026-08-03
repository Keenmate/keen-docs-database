set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Resource access rows
    DELETE FROM auth.resource_access WHERE created_by = 'projtest';

    -- Sub-resources and projects
    DELETE FROM public.project_contact WHERE created_by = 'projtest';
    DELETE FROM public.project_invoice WHERE created_by = 'projtest';
    DELETE FROM public.project_document WHERE created_by = 'projtest';
    DELETE FROM public.project WHERE created_by = 'projtest';

    -- Permission assignments for test users/groups only
    DELETE FROM auth.permission_assignment WHERE user_id IN (
        SELECT user_id FROM auth.user_info WHERE code LIKE 'projtest_%'
    );
    DELETE FROM auth.permission_assignment WHERE user_group_id IN (
        SELECT user_group_id FROM auth.user_group WHERE code LIKE 'projtest_%'
    );

    -- Permission cache for test users
    DELETE FROM auth.user_permission_cache WHERE user_id IN (
        SELECT user_id FROM auth.user_info WHERE code LIKE 'projtest_%'
    );

    -- Group ID cache for test users
    DELETE FROM auth.user_group_id_cache WHERE user_id IN (
        SELECT user_id FROM auth.user_info WHERE code LIKE 'projtest_%'
    );

    -- Group members and groups
    DELETE FROM auth.user_group_member WHERE created_by = 'projtest';
    DELETE FROM auth.user_group WHERE code LIKE 'projtest_%';

    -- Tenant-user links
    DELETE FROM auth.tenant_user WHERE user_id IN (
        SELECT user_id FROM auth.user_info WHERE code LIKE 'projtest_%'
    );

    -- Users
    DELETE FROM auth.user_info WHERE code LIKE 'projtest_%';

    -- Drop test data table
    DROP TABLE IF EXISTS public._projtest_data;

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Projects App Test Suite - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All tests passed:';
    RAISE NOTICE '  001 Project CRUD:';
    RAISE NOTICE '    1. Alice creates project';
    RAISE NOTICE '    2. Dave denied (no RBAC)';
    RAISE NOTICE '    3. Alice sees all projects';
    RAISE NOTICE '    4. Charlie sees only Beta';
    RAISE NOTICE '    5. Bob sees only Alpha (group)';
    RAISE NOTICE '    6. Alice gets specific project';
    RAISE NOTICE '    7. Charlie denied get_project on Alpha';
    RAISE NOTICE '    8. Alice deletes project';
    RAISE NOTICE '  002 Sub-Resource CRUD:';
    RAISE NOTICE '    1. Alice creates document (inherited write)';
    RAISE NOTICE '    2. Bob creates document (group inherited write)';
    RAISE NOTICE '    3. Charlie denied document (no ACL)';
    RAISE NOTICE '    4. Alice creates invoice';
    RAISE NOTICE '    5. Bob denied invoice (explicit deny on project.invoices)';
    RAISE NOTICE '    6. Bob creates contact (group inherited write)';
    RAISE NOTICE '    7. Alice gets documents';
    RAISE NOTICE '    8. Alice gets invoices';
    RAISE NOTICE '    9. Dave denied by RBAC';
    RAISE NOTICE '  003 Hierarchy Inheritance:';
    RAISE NOTICE '    1. project grant cascades to project.documents';
    RAISE NOTICE '    2. project grant cascades to project.invoices';
    RAISE NOTICE '    3. project grant cascades to project.contacts';
    RAISE NOTICE '    4. Sub-type deny blocks only that sub-type';
    RAISE NOTICE '    5. Project read cascades to all sub-types';
    RAISE NOTICE '    6. Read-only grant does not give write';
    RAISE NOTICE '    7. Access matrix returns full grid';
    RAISE NOTICE '  004 Group Access:';
    RAISE NOTICE '    1. Group read on project';
    RAISE NOTICE '    2. Group write cascades to sub-types';
    RAISE NOTICE '    3. No delete via group';
    RAISE NOTICE '    4. User deny overrides group on sub-type';
    RAISE NOTICE '    5. New group propagates access';
    RAISE NOTICE '    6. Effective flags show sources';
    RAISE NOTICE '  005 Share Workflow:';
    RAISE NOTICE '    1. No initial access';
    RAISE NOTICE '    2. Alice shares with Charlie';
    RAISE NOTICE '    3. Charlie gains project access';
    RAISE NOTICE '    4. Charlie reads all sub-resources';
    RAISE NOTICE '    5. Read-only share (no write)';
    RAISE NOTICE '    6. Alice revokes access';
    RAISE NOTICE '    7. Multiple flags granted';
    RAISE NOTICE '';
END $$;
