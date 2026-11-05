# Design

## Context

See `proposal.md` for motivation and `specs/tag-list-api/spec.md` for the behavior contract.

`AdditionalTagsController` currently runs `require_admin` for every action. It already declares `accept_api_auth :index`, validates `type` against `manageable_tag_columns`, resolves a model that responds to `available_tags`, and serializes `id`, `name`, and `count` through the existing API template.

`Issue.available_tags` defaults to `view_issue_tags`. `AdditionalTag.available_tags` defaults to `User.current`, restricts projects through `Project.allowed_to_condition`, applies the optional project/subproject bounds, and groups taggings with `COUNT(DISTINCT taggable_id)`. It does not use issue visibility. `WikiPage.available_tags` has its own permission and joins. These model contracts already implement the required scoping.

Redmine 7.0.2 provides the needed primitives: `require_login` returns 401 for unauthenticated JSON/XML requests when API authentication is enabled; `api_request?` recognizes those formats; `Project.find` accepts ids and identifiers; `Project#visible?` checks project visibility. A bare `find_project` does not itself enforce visibility, while `check_project_privacy` can return 403 for an invisible project, so neither alone satisfies the requested 404 behavior.

The local smoke suite is transactional, refuses database hosts other than `db`, and already loads the Rails environment without the fixture-based upstream test harness. The functional test `test_index_without_permission` currently asserts non-admin API denial and must change. The integration tests document the existing JSON/XML admin payload but depend on unavailable local fixtures.

## Goals / Non-Goals

**Goals:**
- Keep the security change local to index authorization and lookup, reusing the existing permission-aware tag aggregation.
- Verify the API boundary, project intersection, and scoped counts with an independent test oracle.
- Preserve the API serializer and management-action guards rather than introduce a second tag lookup or authorization system.

**Non-Goals:**
- No issue-level visibility filtering, new permission, model aggregation change, schema migration, or custom SQL in the controller.
- No refactoring of `manageable_tag_columns`, management actions, other API endpoints, routes, or tag-type mappings. In particular, do not fix or expand existing wiki/type resolution while implementing this issue-list change.
- No API documentation file or upstream fixture database setup.

## Decisions

### 1. Separate authenticated REST listing from admin management

Scope the existing `require_admin` callback to actions other than index. Add `require_login` for index and retain `accept_api_auth :index`. At the beginning of index, before type validation or tag lookup, require admin for non-API requests using Redmine's existing format/auth helpers. This preserves non-admin HTML 403 even if type is absent, and preserves the valid admin HTML redirect and existing admin type errors.

All other actions remain under the unchanged admin callback. Do not grant API-key authentication to other actions or alter their bodies. Use normal session authentication in the representative edit and merge POST denial test so it exercises the admin guard rather than an API authentication failure.

Alternative rejected: remove the admin guard globally or only put it in mutation actions. Both would unintentionally expose edit/context-menu reads and risk missing future actions. Alternative rejected: require a global `view_issue_tags` authorization for index. A logged-in requester with no permitted projects must receive a successful empty list rather than 403.

### 2. Resolve and visibility-check optional projects explicitly

For API listing with a valid accepted type, treat nonblank `params[:project_id]` as an optional selector. Resolve it with `Project.find`, check `project.visible?(User.current)`, and render 404 with an immediate return if invisible. Handle `ActiveRecord::RecordNotFound` from that lookup as 404, without swallowing unrelated lookup/query exceptions. Keep the resolved project local to the index lookup; do not replace the API with a core project-controller authorization flow.

Pass the project into the existing model API; do not manually expand subprojects or require tag permission on the selected parent before querying. Parent/descendant permissions are intersected by the model, so a visible parent without tag permission can still select permitted descendants when subproject display is enabled. HTML index keeps its existing type-validation/redirect behavior rather than gaining API project-selection errors.

Alternative rejected: `Project.visible.find` without handling identifier lookup, or numeric coercion, which could lose Redmine identifier semantics. Alternative rejected: `check_project_privacy`/`authorize`, which do not provide the required invisible-project 404 and empty-list behavior.

### 3. Delegate aggregation to the selected model without bypassing defaults

Keep the current type allowlist, model resolution, and `respond_to?(:available_tags)` guard unchanged. Call `klass.available_tags(project: project)` only when a project is selected; otherwise retain the existing `klass.available_tags` call with no options. Do not pass `user:` because `AdditionalTag.available_tags` already defaults to `User.current`. Preserve the model's default permission, preconditions, joins, grouping, and ordering. For issues this yields the distinct union and distinct issue counts after project permission and hierarchy restrictions; there is no `Issue.visible` filter and no use of global `taggings_count` as the API usage count.

Admins use the same path, retaining the existing lookup when no project is selected; there is no separate unrestricted admin branch.

Leave `@count`, `@tag_type`, and `index.api.rsb` unchanged. Existing enabled/unsupported type behavior, including other models' native permission defaults, is preserved rather than generalized into a new issue-only registry. `manageable_tag_columns` already calculates counts while discovering types; its extra work is accepted in this focused change.

Alternative rejected: gather `Project.visible` ids in the controller, which would mistake project visibility for tag permission. Alternative rejected: hard-code an issue query for all types, or enforce `view_issue_tags` on every model. Alternative rejected: filter through issue visibility, which contradicts the operator's deliberate project-only policy.

### 4. Add independent, runnable controller smoke coverage

Add an `AdditionalTagsController` smoke test class to `test/redmine7_smoke.rb`, retaining the existing local-host guard, transaction rollback, test job adapter, and setting cleanup. Use a non-admin user, one role with `view_issues` and `view_issue_tags`, and one role with `view_issues` only. Fixtures comprise a permitted project with one permitted and one denied child, a visible tag-denied project, a private project the user does not belong to, shared and exclusive tags, and one private issue the requester cannot view. The visible tag-denied project can be public for the anonymous-access scenario.

Compute expected results independently: enumerate projects and call `user.allowed_to?(:view_issue_tags, project)` per project; for project selection, intersect with the fixture's selected project scope; read ordinary issue ids and raw `AdditionalTagging` rows for `taggable_type: 'Issue'`; group unique issue ids by tag and read tag names/ids directly. Do not call `available_tags`, `tag_access`, `visible_condition`, or the controller/helper aggregation path to build expectations. Use this oracle for complete tag-set and count comparisons, rather than checking only one known tag.

Plan one smoke test per spec scenario (15 tests), keeping related assertions together: JSON API-key success with an XML 200 assertion; anonymous 401; unique permitted-project union; private-issue scoped count; no-permission empty list; shared-tag scoped count; identifier-based project narrowing; visible tag-denied empty list; enabled subproject display with permitted/denied children; missing-project 404; invisible-project 404; unchanged admin result; non-admin HTML 403; admin HTML redirect; and edit/merge POST 403 with unchanged data after the merge. The private-issue count is the sole issue-visibility test. Numeric ids use the same `Project.find` path, and subproject handling remains existing model code.

Use simple identity helpers for session authentication, API-key-only authentication, and anonymous requests; each resets the session, API header, and `User.current`. No cache-isolation machinery is needed.

Update/rename `test/functional/additional_tags_controller_test.rb#test_index_without_permission` to assert authenticated non-admin API success with scoped results, including the no-tag-permission empty-list case. Retain a separate non-admin HTML denial assertion. This upstream test update cannot be executed locally without the fixture test database and must be reported as not run. Existing integration tests remain unchanged; their coverage of preserved API behavior does not need duplicating in the smoke suite.

Alternative rejected: compute new smoke expectations with `Issue.available_tags`, as existing project API smoke tests do. That repeats the implementation and cannot expose a shared permission/counting regression. Alternative rejected: rely only on upstream functional/integration tests, which are not runnable in this environment.

## Risks / Trade-offs

- [Project-only policy reveals tag names and aggregate usage from individually hidden issues] → This is an explicit operator decision, consistent with existing plugin surfaces; protect it with focused tests rather than silently adding issue visibility.
- [Making an action public to non-admins also exposes HTML or adjacent management routes] → Require login for index, check non-API admin status before any work, retain the admin callback on every other action, and test HTML plus representative read/mutation denials.
- [Shared tags or subproject counts leak usage outside allowed projects] → Keep model permission intersection and distinct counting; test complete results against raw taggings, including shared tags in denied projects.
- [Local smoke data and inherited admin credentials can obscure regressions] → Use controlled transactional fixtures, independent full-result expectations, explicit identity resets, and API-key-only/anonymous cases.
- [Type discovery performs extra queries and contains existing model-resolution quirks] → Leave the helper and mappings untouched; this change is authorization/optional project selection, not a type-registry or performance refactor.
- [Fixture-based upstream tests remain unexecuted locally] → Update the contradictory functional test, run the standalone smoke suite during implementation, and explicitly report upstream tests as not run.

## Migration Plan

No data migration or new configuration is required. Run the standalone suite against the existing local container from `/home/andre/projects/redmine/docker`:

```sh
docker compose exec -T app bundle exec ruby -r ./config/environment.rb plugins/additional_tags/test/redmine7_smoke.rb
```

Record its complete result and distinguish it from unexecuted upstream fixture tests. Review the controller/test-only diff; the PR target is `optimus-redmine-7-additional-tags`. Rolling back the controller change restores admin-only list access without a data rollback.
