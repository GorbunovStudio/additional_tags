# Spec Delta

## ADDED Requirements

### Requirement: API clients can search tag names within their permitted scope

For JSON and XML issue tag lists, a nonblank `q` SHALL restrict the existing permitted tag set to names containing the whitespace-trimmed query as a case-insensitive substring. Counts SHALL remain scoped to permitted projects, not global usage. Search SHALL retain `tags` entries with `id`, `name`, and `count`, `total_count` equal to the number of returned tags, and `tag_type`. Search SHALL affect API responses only, leaving HTML behavior unchanged.

#### Scenario: Case-insensitive substring search retains permission scope and scoped counts
- **GIVEN** permitted, tag-denied, and inaccessible projects contain tags with the same name substring
- **AND** a shared matching tag is used on two issues in permitted projects and three issues outside them
- **WHEN** an authenticated non-admin searches the JSON and XML issue tag lists using a differently cased substring from inside those names
- **THEN** only matching tags used in permitted projects are returned
- **AND** the shared tag has count two, denied-only and inaccessible-only tags are absent, and the response metadata describes the filtered list

### Requirement: Search results are ordered by scoped usage then name

When `q` is nonblank after whitespace stripping, the issue tag list SHALL be ordered by scoped `count` descending, with ties ordered by name ascending.

#### Scenario: Nonblank query orders counts descending and tied names ascending
- **GIVEN** matching permitted tags have different scoped counts and at least two tags share a count
- **WHEN** an authenticated requester searches for their common substring
- **THEN** higher scoped counts precede lower counts and names within each tied count are ascending

### Requirement: Search and project selection intersect

When both a nonblank `q` and `project_id` are supplied, the issue tag list SHALL intersect the name match with the existing permitted project selection, including its existing subproject behavior. Counts SHALL use only that selected permitted project scope.

#### Scenario: Query and project selection each narrow the result
- **GIVEN** a permitted selected project has matching and nonmatching tags, and matching tags also occur outside its scope
- **WHEN** the requester lists issue tags with both a substring query and that project's identifier
- **THEN** nonmatching tags in the selected scope and matching tags used only outside it are absent
- **AND** a returned tag used both inside and outside the scope counts only distinct issues inside it

### Requirement: Search treats LIKE special characters literally

Within `q`, percent (`%`), underscore (`_`), and backslash (`\`) SHALL match those characters literally rather than acting as pattern syntax.

#### Scenario: Literal query characters do not expand the match
- **GIVEN** permitted tags contain literal percent, underscore, or backslash characters and other tags would match only if those query characters were interpreted as pattern syntax
- **WHEN** the requester searches separately for substrings containing each of those characters
- **THEN** only names containing the corresponding literal substring are returned

### Requirement: Blank search preserves the plain list and ordering

An absent `q`, empty `q`, or `q` containing only whitespace SHALL leave the issue tag list unfiltered and name-ascending, with the plain list's scoped tags and counts.

#### Scenario: Blank query keeps the plain name-ordered list
- **GIVEN** permitted tags have differing counts so usage order differs from name order
- **WHEN** the requester supplies an empty or whitespace-only `q`
- **THEN** the tags and counts equal the list without `q` and the returned sequence remains name-ascending
