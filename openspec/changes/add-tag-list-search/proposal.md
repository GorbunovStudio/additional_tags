# Proposal

## Why

API clients need to search the tag vocabulary without downloading the whole list. The existing autocomplete endpoint does not support API-key authentication, while the tag list API already provides the required permission scope and counts.

## What Changes

- Accept optional `q` on the JSON and XML tag list: a literal, case-insensitive name substring within the existing permission and optional project scope.
- Order nonblank searches by scoped count descending, then name ascending; preserve the plain name-ordered list when `q` is absent or blank after whitespace stripping.
- Treat `%`, `_`, and backslash literally, not as LIKE pattern syntax.
- Keep the response shape, authentication, project lookup, HTML behavior, and management restrictions unchanged.
- Add exactly five scenario tests to `OptimusTagListApiSmokeTest`, reusing its fixtures and independent oracle.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tag-list-api`: Add optional substring search and search-specific ordering through ADDED requirements; the existing requirements continue to describe the plain list and its access rules.

## Impact

- Implementation is limited to `AdditionalTagsController#index` in `app/controllers/additional_tags_controller.rb` and tests in `test/redmine7_smoke.rb`.
- Reuse `available_tags` options `name_like`, `sort_by: 'count'`, and `order: 'DESC'`; no model, helper, view, route, or autocomplete changes.
- No API documentation file, new dependencies, migrations, pagination, or production operations.
- This is a follow-up on branch `allow-non-admin-tag-list`, PR #1, targeting `optimus-redmine-7-additional-tags`; no Redmine ticket work is involved.
