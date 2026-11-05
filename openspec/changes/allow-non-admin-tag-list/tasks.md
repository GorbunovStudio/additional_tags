# Tasks

Implementation is limited to `AdditionalTagsController`'s index authorization/lookup path and its tests. Follow `design.md` and `specs/tag-list-api/spec.md`; leave helpers, models, routes, serializers, type mappings, and other action bodies unchanged. No API documentation file is needed.

Run the smoke suite from `/home/andre/projects/redmine/docker`:

```sh
docker compose exec -T app bundle exec ruby -r ./config/environment.rb plugins/additional_tags/test/redmine7_smoke.rb
```

## 1. Independent smoke fixtures and expected results

- [ ] 1.1 Add an `AdditionalTagsController` class to `test/redmine7_smoke.rb` with a non-admin user, a role with `view_issues` + `view_issue_tags`, a role with `view_issues` only, a permitted project with one permitted and one denied child, a visible tag-denied project (public for the anonymous scenario), a private non-member project, shared/exclusive tags, and one private issue. Verify fixture permissions and that the user cannot view the private issue; preserve the existing host guard and transaction/setting cleanup.
- [ ] 1.2 Add an independent oracle using per-project `User#allowed_to?(:view_issue_tags, project)`, raw issue taggings, distinct issue ids per tag, and direct tag id/name reads; intersect the fixture project scope when selected. Verify the full returned tag sets and counts in the retained scenario tests without using `available_tags` or production aggregation helpers in expectations.
- [ ] 1.3 Add simple session, API-key-only, and anonymous identity helpers that reset the session, API header, and `User.current`. Verify the retained authentication tests use the intended identity without inherited admin credentials; no cache-isolation machinery is needed.

## 2. Authenticated project-permission-scoped listing

- [ ] 2.1 Restrict the existing `require_admin` callback to actions other than index, require login for index, retain `accept_api_auth :index`, and require admin for non-API index before type validation. Add one smoke test per retained scenario: non-admin API-key JSON 200 with the scoped list plus XML 200 for the same user; anonymous 401 despite public-project tags; non-admin HTML 403; and the existing admin HTML redirect. Verify the scoped list against the independent oracle.
- [ ] 2.2 Retain type/model validation and the existing no-options `klass.available_tags` call when no project is selected, relying on its default current user and permissions. Add one smoke test each for the unique permitted-project union, private-issue scoped count, no-permission 200/empty result, and shared-tag counts excluding denied-project usage; verify full sets and counts against the independent oracle. The private-issue count is the only issue-visibility test.
- [ ] 2.3 Add one smoke test for the unchanged admin list without project selection; verify its tag set and counts against the independent raw-data oracle. Leave existing payload, ordering, and type-validation coverage to the upstream tests.
- [ ] 2.4 Add one session-authenticated non-admin smoke test combining edit and merge POST denials. Verify both return 403 and the merge changes no tags or taggings; leave the unchanged admin callback and management actions untouched.
- [ ] 2.5 Replace/rename the contradictory `test/functional/additional_tags_controller_test.rb#test_index_without_permission` assertion with permission-scoped non-admin API success and no-tag-permission empty-list assertions, plus a separate non-admin HTML 403 test. Verify by reviewing fixture permissions and assertion expectations against the new spec; explicitly record that this functional suite cannot run locally without the Redmine fixture test database, rather than reporting it as passing.

## 3. Optional project restriction

- [ ] 3.1 Add optional nonblank API `project_id` lookup using `Project.find`, explicit `visible?(User.current)` checking, immediate 404 on invisible projects, and a narrowly handled missing-project lookup. Call `klass.available_tags(project: project)` only when a project is selected, without passing `user:`. Add one smoke test each for identifier-based narrowing, a visible tag-denied project returning 200/empty, a missing project returning 404, and an invisible project returning 404; verify selected full sets/counts against the independent oracle.
- [ ] 3.2 Add one smoke test with default subproject display enabled, selecting the permitted parent. Verify its tags/counts include the permitted child and exclude the denied child against the independent oracle; leave subproject handling in the existing model code.

## 4. Integrated verification and scope review

- [ ] 4.1 Run the complete standalone smoke command above after implementation, including the pre-existing 13 smoke tests and all new index tests; record the exact command, full output, test/assertion totals, and exit status. Verify it exits successfully with no failures/errors and report upstream functional/integration suites as not run because their fixture database is unavailable.
- [ ] 4.2 Run `openspec validate allow-non-admin-tag-list --strict` and review the final diff with `git diff --check` and `git diff --stat`. Verify strict validation succeeds, whitespace checks are clean, implementation edits are confined to the controller/index authorization path and tests, no helper/model/API-documentation refactor slipped in, and the eventual PR target remains `optimus-redmine-7-additional-tags` rather than `main`.
