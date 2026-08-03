set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Projects App Test Suite - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create test users, groups, assign perms, create projects, sub-resources, ACL
-- ============================================================================
DO $$
DECLARE
    __alice_id   bigint;
    __bob_id     bigint;
    __charlie_id bigint;
    __dave_id    bigint;   -- user with NO project permissions (RBAC denied)
    __editors_group_id integer;

    __alpha_id   bigint;
    __beta_id    bigint;

    __doc1_id    bigint;
    __doc2_id    bigint;
    __doc3_id    bigint;
    __inv1_id    bigint;
    __inv2_id    bigint;
    __inv3_id    bigint;
    __con1_id    bigint;
    __con2_id    bigint;
    __con3_id    bigint;
BEGIN
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create test users
    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, email, can_login, original_username)
    VALUES ('projtest', 'projtest', 'Test Alice', 'projtest_alice', 'projtest_alice@test.com', 'projtest_alice@test.com', true, 'projtest_alice@test.com')
    RETURNING user_id INTO __alice_id;

    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, email, can_login, original_username)
    VALUES ('projtest', 'projtest', 'Test Bob', 'projtest_bob', 'projtest_bob@test.com', 'projtest_bob@test.com', true, 'projtest_bob@test.com')
    RETURNING user_id INTO __bob_id;

    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, email, can_login, original_username)
    VALUES ('projtest', 'projtest', 'Test Charlie', 'projtest_charlie', 'projtest_charlie@test.com', 'projtest_charlie@test.com', true, 'projtest_charlie@test.com')
    RETURNING user_id INTO __charlie_id;

    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, email, can_login, original_username)
    VALUES ('projtest', 'projtest', 'Test Dave', 'projtest_dave', 'projtest_dave@test.com', 'projtest_dave@test.com', true, 'projtest_dave@test.com')
    RETURNING user_id INTO __dave_id;

    -- Link users to primary tenant
    INSERT INTO auth.tenant_user (created_by, tenant_id, user_id) VALUES
        ('projtest', 1, __alice_id),
        ('projtest', 1, __bob_id),
        ('projtest', 1, __charlie_id),
        ('projtest', 1, __dave_id);

    -- Project Editors group with Bob as member
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_active, is_assignable)
    VALUES ('projtest', 'projtest', 1, 'Projtest Editors', 'projtest_editors', true, true)
    RETURNING user_group_id INTO __editors_group_id;

    INSERT INTO auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    VALUES ('projtest', __editors_group_id, __bob_id, 'manual');

    -- RBAC assignments:
    --   Alice   = system_admin + project_user (full access)
    --   Bob     = project_user
    --   Charlie = project_user
    --   Dave    = NO project permissions (RBAC will block)
    PERFORM unsecure.assign_permission_as_system(null::integer, __alice_id, 'system_admin');
    PERFORM unsecure.assign_permission_as_system(null::integer, __alice_id, 'project_user');
    PERFORM unsecure.assign_permission_as_system(null::integer, __bob_id, 'project_user');
    PERFORM unsecure.assign_permission_as_system(null::integer, __charlie_id, 'project_user');
    -- Dave gets no assignment

    -- Projects
    INSERT INTO public.project (tenant_id, title, status, created_by_user, created_by, updated_by)
    VALUES (1, 'Test Project Alpha', 'active', __alice_id, 'projtest', 'projtest')
    RETURNING project_id INTO __alpha_id;

    INSERT INTO public.project (tenant_id, title, status, created_by_user, created_by, updated_by)
    VALUES (1, 'Test Project Beta', 'active', __alice_id, 'projtest', 'projtest')
    RETURNING project_id INTO __beta_id;

    -- Sub-resources for Alpha
    INSERT INTO public.project_document (project_id, tenant_id, title, content_type, size_bytes, created_by_user, created_by, updated_by)
    VALUES (__alpha_id, 1, 'Test Requirements.pdf', 'application/pdf', 102400, __alice_id, 'projtest', 'projtest')
    RETURNING document_id INTO __doc1_id;

    INSERT INTO public.project_document (project_id, tenant_id, title, content_type, size_bytes, created_by_user, created_by, updated_by)
    VALUES (__alpha_id, 1, 'Test Design.md', 'text/markdown', 8192, __alice_id, 'projtest', 'projtest')
    RETURNING document_id INTO __doc2_id;

    INSERT INTO public.project_invoice (project_id, tenant_id, invoice_number, amount, status, created_by_user, created_by, updated_by)
    VALUES (__alpha_id, 1, 'TEST-INV-001', 5000.00, 'paid', __alice_id, 'projtest', 'projtest')
    RETURNING invoice_id INTO __inv1_id;

    INSERT INTO public.project_invoice (project_id, tenant_id, invoice_number, amount, status, created_by_user, created_by, updated_by)
    VALUES (__alpha_id, 1, 'TEST-INV-002', 3000.00, 'draft', __alice_id, 'projtest', 'projtest')
    RETURNING invoice_id INTO __inv2_id;

    INSERT INTO public.project_contact (project_id, tenant_id, display_name, email, role, created_by_user, created_by, updated_by)
    VALUES (__alpha_id, 1, 'Test Client Smith', 'smith@test.com', 'client', __alice_id, 'projtest', 'projtest')
    RETURNING contact_id INTO __con1_id;

    INSERT INTO public.project_contact (project_id, tenant_id, display_name, email, role, created_by_user, created_by, updated_by)
    VALUES (__alpha_id, 1, 'Test Dev Jones', 'jones@test.com', 'member', __alice_id, 'projtest', 'projtest')
    RETURNING contact_id INTO __con2_id;

    -- Sub-resources for Beta
    INSERT INTO public.project_document (project_id, tenant_id, title, content_type, size_bytes, created_by_user, created_by, updated_by)
    VALUES (__beta_id, 1, 'Test Proposal.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 51200, __alice_id, 'projtest', 'projtest')
    RETURNING document_id INTO __doc3_id;

    INSERT INTO public.project_invoice (project_id, tenant_id, invoice_number, amount, status, created_by_user, created_by, updated_by)
    VALUES (__beta_id, 1, 'TEST-INV-003', 10000.00, 'draft', __alice_id, 'projtest', 'projtest')
    RETURNING invoice_id INTO __inv3_id;

    INSERT INTO public.project_contact (project_id, tenant_id, display_name, email, role, created_by_user, created_by, updated_by)
    VALUES (__beta_id, 1, 'Test Manager Lee', 'lee@test.com', 'client', __alice_id, 'projtest', 'projtest')
    RETURNING contact_id INTO __con3_id;

    -- ACL grants:
    --   Alice: read+write+delete+share on both projects (at 'project' level — cascades)
    PERFORM auth.grant_resource_access('projtest', 1, 'projtest', 'project', __alpha_id,
        _target_user_id := __alice_id, _access_flags := array['read','write','delete','share']);
    PERFORM auth.grant_resource_access('projtest', 1, 'projtest', 'project', __beta_id,
        _target_user_id := __alice_id, _access_flags := array['read','write','delete','share']);

    --   Editors group (Bob is member): read+write on Alpha (at 'project' level — cascades)
    PERFORM auth.grant_resource_access('projtest', 1, 'projtest', 'project', __alpha_id,
        _user_group_id := __editors_group_id, _access_flags := array['read','write']);

    --   Charlie: read on Beta only (at 'project' level — cascades to all sub-types)
    PERFORM auth.grant_resource_access('projtest', 1, 'projtest', 'project', __beta_id,
        _target_user_id := __charlie_id, _access_flags := array['read']);

    --   Bob: denied read+write on project.invoices for Alpha
    --   (can see docs/contacts via group grant on 'project', but NOT invoices)
    PERFORM auth.deny_resource_access('projtest', 1, 'projtest', 'project.invoices', __alpha_id,
        _target_user_id := __bob_id, _access_flags := array['read','write']);

    -- Store IDs in persistent table for cross-file access
    CREATE TABLE IF NOT EXISTS public._projtest_data (
        key text PRIMARY KEY,
        val bigint
    );
    DELETE FROM public._projtest_data;
    INSERT INTO _projtest_data VALUES
        ('alice_id',          __alice_id),
        ('bob_id',            __bob_id),
        ('charlie_id',        __charlie_id),
        ('dave_id',           __dave_id),
        ('editors_group_id',  __editors_group_id),
        ('alpha_id',          __alpha_id),
        ('beta_id',           __beta_id),
        ('doc1_id',           __doc1_id),
        ('doc2_id',           __doc2_id),
        ('doc3_id',           __doc3_id),
        ('inv1_id',           __inv1_id),
        ('inv2_id',           __inv2_id),
        ('inv3_id',           __inv3_id),
        ('con1_id',           __con1_id),
        ('con2_id',           __con2_id),
        ('con3_id',           __con3_id);

    RAISE NOTICE 'SETUP: Users: Alice(%), Bob(%), Charlie(%), Dave(%)', __alice_id, __bob_id, __charlie_id, __dave_id;
    RAISE NOTICE 'SETUP: Group: Projtest Editors(%)', __editors_group_id;
    RAISE NOTICE 'SETUP: Projects: Alpha(%), Beta(%)', __alpha_id, __beta_id;
    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;
