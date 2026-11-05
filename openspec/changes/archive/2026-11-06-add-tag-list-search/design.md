# Design

## Context

See `proposal.md` for motivation and `specs/tag-list-api/spec.md` for the five acceptance scenarios.

`AdditionalTagsController#index` currently resolves a manageable type and calls its `available_tags`, optionally with a visible project. The API view serializes `id`, `name`, and `count`, with `total_count` and `tag_type`. `AdditionalTag.available_tags` already combines project permissions, project/subproject restrictions, a `name_like` predicate, distinct-issue counts, and ordering. `table_columns` selects the scoped `count` regardless of sort mode; `build_order_sql('count', 'DESC')` already yields `count DESC, additional_tags.name ASC`.

The autocomplete patch demonstrates `name_like` reuse but neither escapes LIKE metacharacters nor provides the API-key endpoint needed here. The main `tag-list-api` spec describes the existing plain list and access rules; optional search is additive, so this delta does not replace any existing requirement or scenario.

## Goals / Non-Goals

**Goals:**
- Compose search and project selection in the same `available_tags` call so filters, counts, and order share one permitted scope.
- Keep query normalization and escaping local to the API branch of `index`.
- Derive test expectations independently from raw rows, not from the production query being tested.

**Non-Goals:**
- No changes to models, helpers, views, routes, autocomplete semantics, or existing permission and authentication logic.
- No new API documentation file, endpoint, pagination, indexing work, dependencies, or database migrations.
- No separate tests for unchanged login, HTML, project-error, management, or type-validation behavior already covered by the suite.

## Decisions

### 1. Build one options hash in index

Retain the current access/type checks and visible-project lookup. For API requests, accumulate any resolved `project` and search options in one hash and call `klass.available_tags(**options).to_a` once. Keep `@count = @tags.count` and the existing serializer unchanged. HTML requests do not consume `q` and retain their current redirect/403 behavior.

This avoids separate search/project query branches that could drop one restriction. Do not fetch a global tag relation or filter serialized results: those alternatives duplicate existing scope logic and risk incorrect counts.

### 2. Normalize and escape before passing name_like

Normalize API `q` using `params[:q].to_s.strip`. Whitespace-only input is absent; trimming nonblank input is the normalization convention for this addition. For a present query, set `name_like` to `ActiveRecord::Base.sanitize_sql_like(q)`. Do not add surrounding `%` in the controller: `available_tags` already supplies the two substring wildcards.

`sanitize_sql_like` escapes `%`, `_`, and backslash, while the existing bound predicate handles SQL value quoting. The verified Redmine database helper uses PostgreSQL `ILIKE` (and `unaccent` when available), MySQL `LIKE`, or `LIKE ... ESCAPE '\'` for other adapters. Escaping therefore retains the platform's matching behavior without changing the shared model. Raw `name_like` would interpret wildcard input; changing the model or autocomplete would broaden the scope of this request.

### 3. Apply count ordering only for a nonblank query

Alongside `name_like`, set `sort_by: 'count'` and `order: 'DESC'`. Reuse the existing count alias and name-ascending tie-break rather than adding SQL, reading global `taggings_count`, sorting in Ruby, or consulting the autocomplete suggestion-order setting. With no normalized query, omit all three search options, preserving the default name-ascending list.

### 4. Extend the existing smoke class with exactly five tests

Reuse `OptimusTagListApiSmokeTest`, its API-key sign-in/request helpers, project hierarchy, tagged issues, `json_tags`, and `expected_issue_tags`. Compute expected search results by selecting from the raw-row oracle with Ruby case-insensitive literal substring matching (`name.downcase.include?(q.downcase)` for the ASCII fixture queries). Do not use `available_tags`, database LIKE, or `sanitize_sql_like` to construct expected matches.

One new test maps to each delta scenario:

1. **Case-insensitive substring and permission scope:** Search with mixed-case `FiXtUrE-`, an interior substring of the existing fixture names. Compare JSON and XML entries to the independently filtered oracle, checking the shared tag's permitted count of two rather than its global count of five, and exclusion of denied-only/private-only tags. Reuse existing fixtures; validate filtered metadata as part of the search response assertions.
2. **Count ordering and ties:** Search the existing fixture prefix and compare the returned name sequence with oracle entries sorted by `[-count, name]`. Existing `priv-count` and `shared` have count two; `child-only` and `parent-only` have count one, exercising both count precedence and tied name order without new fixtures. Read response sequence explicitly; hash equality alone cannot verify order.
3. **Query plus project:** Use `q=only` and `project_id` selecting `@child_ok` by identifier. Compare against `expected_issue_tags(@requester, [@child_ok.id])` filtered by the literal query. Assert `child-only` remains, `shared` is excluded by the query, and `parent-only` is excluded by project selection. In the same scenario test, query `shared` for that project and assert count one, excluding its uses in other permitted and denied projects.
4. **Literal characters:** In this test only, add the minimal literal `%`, `_`, and backslash tag fixtures and contrasting names/taggings needed to detect wildcard expansion or dropped escape characters. Loop over the three character queries within this single test; compare against the independent literal-match oracle.
5. **Blank query:** In one test, compare absent `q` with empty and whitespace-only values using the existing fixtures. Assert oracle tags/counts and the actual name-ascending sequence, demonstrating that blank input does not activate usage ordering. No new fixtures are needed.

The inherited local-database guard and transaction rollback remain intact. Do not create a second test harness or expand coverage with new tests for unchanged behavior.

## Risks / Trade-offs

- [Unescaped or double-escaped LIKE input changes literal matching] → Escape exactly once in `index`; cover all three special characters in the single literal-search test.
- [Search branches accidentally bypass project scope or rank by global usage] → Compose options in one `available_tags` call and compare filtered raw-row oracle results and scoped counts.
- [Ordering assertions pass despite a wrong sequence] → Inspect serialized order separately from payload-map equality, using existing lowercase ASCII fixture names to avoid collation ambiguity.
- [Database-specific case/accent behavior varies] → Reuse `Redmine::Database.like` unchanged; exercise mixed-case ASCII matches on the established local PostgreSQL smoke environment, without introducing a new cross-database test matrix.

## Migration Plan

No data migration or configuration change is needed. Implement only the controller and five scenario tests on the existing PR branch. Verification consists of the existing local smoke suite, Ruby syntax checks, and strict OpenSpec validation. Rollback is removal of the controller/test addition; the plain-list API and stored data need no migration.
