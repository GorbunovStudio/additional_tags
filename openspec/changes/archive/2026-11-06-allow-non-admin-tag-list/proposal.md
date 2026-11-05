# Proposal

## Why

The tag list REST API currently rejects every non-admin, even though the plugin already exposes project-permission-scoped tags in autocomplete, filters, and project API responses. Authenticated non-admins need the same project-scoped issue tag vocabulary without gaining tag-management access.

## What Changes

- Allow authenticated non-admins to use the JSON and XML forms of `AdditionalTagsController#index`; anonymous API requests remain unauthorized (401).
- Return the unique issue tags used in projects where the requester has `view_issue_tags`, with each tag's count restricted to those projects. Deliberately do not apply issue-level visibility.
- Accept an optional `project_id` (numeric id or identifier), returning 404 for a missing or invisible project and intersecting the selected project/subproject scope with the requester's tag permissions.
- Preserve the existing API payload, type validation, model-specific tag lookup behavior, and admin results when no new project restriction is requested.
- Keep HTML index admin-only and preserve its admin redirect; keep edit, update, merge, destroy, and context menu admin-only.
- Add runnable local smoke coverage and replace the upstream functional assertion that all non-admin list requests return 403.

## Capabilities

### New Capabilities

- `tag-list-api`: Authentication, project-permission scoping, scoped usage counts, optional project selection, response compatibility, and the boundary between REST listing and admin tag management.

### Modified Capabilities

None. This is the repository's first capability spec.

## Impact

- Implementation is limited to the index authorization/lookup path in `app/controllers/additional_tags_controller.rb` and its tests, primarily `test/redmine7_smoke.rb` and `test/functional/additional_tags_controller_test.rb`.
- Reuses the existing `available_tags` model API and Redmine login/project visibility primitives. No model, helper, route, serializer, schema, dependency, or API documentation changes are planned.
- The standalone smoke suite is the locally runnable verification. Upstream fixture-based functional/integration suites cannot run in the current environment and must not be reported as passing.
- The branch base and PR target are `optimus-redmine-7-additional-tags`, not `main`.
