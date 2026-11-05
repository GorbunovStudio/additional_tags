# tag-list-api Specification

## Purpose

Provide authenticated API clients with a unique tag vocabulary and usage counts limited by project permissions, without granting access to tag administration.

## Requirements

### Requirement: Authenticated users can list tags through the REST API

The system SHALL allow authenticated non-admins and admins to request `GET /additional_tags.json?type=issue` and `GET /additional_tags.xml?type=issue` when issue tags are enabled. API-key authentication SHALL remain supported.

#### Scenario: Non-admin requests JSON with an API key
- **GIVEN** an active non-admin with a valid API key and issue tags enabled
- **WHEN** the user requests the JSON issue tag list using only API-key authentication
- **THEN** the response is 200 and contains the requester's scoped tag list
- **AND** the XML form also returns 200 for the same user

### Requirement: Anonymous API requests require login

The system SHALL return 401 for an unauthenticated JSON or XML tag list request when the REST API is enabled, even when public projects expose tags to logged-in users or anonymous browsing is otherwise allowed.

#### Scenario: Anonymous requests cannot obtain public-project tags
- **GIVEN** the REST API is enabled, login is not globally required, and a public project has tagged issues
- **WHEN** an unauthenticated client requests the issue tag list in either API format
- **THEN** the response is 401 and does not expose a tag list

### Requirement: Issue tags are scoped by project permission

For `type=issue`, the system SHALL return exactly the unique tags used on at least one issue in a project where the requester has `view_issue_tags`. Project access without that permission SHALL NOT expose tags. Issue-level visibility SHALL NOT further restrict the result.

#### Scenario: Tags from permitted projects are unioned without duplicates
- **GIVEN** two projects grant the requester `view_issue_tags`, a third accessible project does not, and a fourth project is inaccessible
- **AND** some tags are shared across those projects and others are exclusive to each
- **WHEN** the requester lists issue tags without `project_id`
- **THEN** tags used in either permitted project appear once each
- **AND** tags used only in the denied or inaccessible projects are absent

#### Scenario: No permitted tag projects produces an empty list
- **GIVEN** the requester can see projects but has `view_issue_tags` in none of them
- **WHEN** the requester lists issue tags
- **THEN** the response is 200 with no tags and `total_count` equal to zero

### Requirement: Counts reflect only the selected permitted projects

Each issue tag's `count` SHALL equal the number of distinct issues carrying that tag within the requester's permitted project scope, after any project restriction. Issues outside that scope SHALL NOT contribute to the count.

#### Scenario: Shared tags do not leak denied-project usage counts
- **GIVEN** a tag is used on two issues in permitted projects and three issues outside them
- **WHEN** the requester lists issue tags
- **THEN** the tag appears once with `count` equal to two

#### Scenario: Private issues contribute to the scoped count
- **GIVEN** a tag is used on one public and one private issue in a permitted project
- **WHEN** a requester who cannot view the private issue lists issue tags
- **THEN** that tag's `count` is two

### Requirement: Optional project selection narrows the permitted scope

The system SHALL accept `project_id` as a project id or identifier and intersect that project scope with the requester's tag permissions. A visible project without tag permission SHALL yield an empty list unless an included subproject grants permission.

#### Scenario: Project selected by identifier narrows the list
- **GIVEN** a visible permitted project and tags used outside that project's scope
- **WHEN** the requester lists issue tags using the project's identifier
- **THEN** only tags and counts from that project's permitted scope are returned

#### Scenario: A visible project without tag permission yields an empty list
- **GIVEN** a visible project without `view_issue_tags` and no included permitted subprojects
- **WHEN** the requester selects that project
- **THEN** the response is 200 with no tags and `total_count` equal to zero

### Requirement: Project selection respects the subproject display setting

Project selection SHALL retain Redmine's existing default subproject issue display behavior and intersect the included projects with the requester's tag permissions.

#### Scenario: Enabled subproject display includes a permitted child and excludes a denied child
- **GIVEN** a permitted selected project with one permitted child and one denied child
- **AND** default subproject issue display is enabled
- **WHEN** the requester selects that project for the issue tag list
- **THEN** tags and counts include the selected project and permitted child
- **AND** uses in the denied child are excluded

### Requirement: Missing and invisible project selections return not found

For an authenticated API request with a valid enabled tag type, the system SHALL return 404 when a nonblank `project_id` does not resolve to a project or resolves to a project invisible to the requester. The response SHALL NOT expose that project's tags.

#### Scenario: Missing project returns not found
- **WHEN** an authenticated requester selects a nonexistent project for a valid issue tag list request
- **THEN** the response is 404 rather than an unrestricted tag list

#### Scenario: Invisible project returns not found
- **GIVEN** a private project invisible to the requester
- **WHEN** the requester selects it for a valid issue tag list request
- **THEN** the response is 404 rather than 403 or a tag list

### Requirement: Admin list behavior remains compatible

For requests without project selection, admins SHALL retain their existing tag sets and usage counts. The existing response format and type validation SHALL remain unchanged.

#### Scenario: Existing admin request keeps its result
- **GIVEN** unchanged tag data and settings
- **WHEN** an admin requests the issue tag list without `project_id`
- **THEN** the tags and counts match the existing admin list behavior

### Requirement: HTML listing and tag management remain admin-only

The system SHALL keep HTML index admin-only: authenticated non-admins receive 403 and admins with a valid tag type retain the redirect to tag management. Tag management actions SHALL remain admin-only.

#### Scenario: Admin HTML index keeps its redirect
- **WHEN** an admin requests HTML index with a valid enabled issue tag type
- **THEN** the response redirects to the plugin's manage-tags settings screen

#### Scenario: Non-admin HTML index is forbidden
- **WHEN** an authenticated non-admin requests HTML index
- **THEN** the response is 403 and does not redirect to tag management

#### Scenario: Listing does not grant management access
- **GIVEN** an authenticated non-admin who can successfully list issue tags
- **WHEN** the user requests edit and submits a merge POST
- **THEN** both responses are 403
- **AND** the merge changes no tag or tagging
