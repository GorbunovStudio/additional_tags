require 'minitest/autorun'
require 'action_controller/test_case'

class OptimusTagsSmokeTest < ActionController::TestCase
  setup do
    raise 'Run only against the upgraded local db service' unless ActiveRecord::Base.connection_db_config.host == 'db'
    @connection = ActiveRecord::Base.connection
    @connection.begin_transaction
    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @routes = Rails.application.routes
    @user = User.active.where(admin: true).first!
    @request.session[:user_id] = @user.id
    @request.session[:tk] = @user.generate_session_token
    @request.headers['X-Redmine-API-Key'] = @user.api_key
    User.current = @user
    Setting.rest_api_enabled = '1'
    @issue = Issue.joins(:tags, :project).merge(Project.active).where(is_private: false).first!
    @project = @issue.project
  end

  teardown do
    @connection.rollback_transaction if @connection
    ActiveJob::Base.queue_adapter = @queue_adapter if @queue_adapter
    User.current = nil
    Setting.clear_cache
  end

  def assert_tag_payload(record, expected_names)
    tags = record.fetch('tags')
    assert_equal expected_names.sort, tags.map { |tag| tag.fetch('name') }.sort
    assert tags.all? { |tag| tag.fetch('id').is_a?(Integer) }
  end

  def become_read_only_user
    role = Role.create!(name: 'Optimus tag fixture reader', permissions: [:view_issues])
    reader = User.new(login: 'optimus-tags-fixture', firstname: 'Optimus', lastname: 'Fixture',
      mail: 'optimus-tags-fixture@example.invalid', status: User::STATUS_ACTIVE)
    reader.password = reader.password_confirmation = 'OptimusTagsFixture_2026!'
    reader.save!
    Member.create!(project: @project, user: reader, roles: [role])
    @request.session[:user_id] = reader.id
    @request.session[:tk] = reader.generate_session_token
    @request.headers['X-Redmine-API-Key'] = reader.api_key
    User.current = reader
  end
end

class OptimusIssueTagsApiSmokeTest < OptimusTagsSmokeTest
  tests IssuesController

  def test_issue_detail_preserves_include_tags
    get :show, params: {id: @issue.id, format: 'json', include: 'tags'}
    assert_response :success
    assert_tag_payload JSON.parse(response.body).fetch('issue'), @issue.tags.map(&:name)
  end

  def test_issue_list_preserves_include_tags
    get :index, params: {format: 'json', issue_id: @issue.id, status_id: '*', include: 'tags'}
    assert_response :success
    record = JSON.parse(response.body).fetch('issues').find { |issue| issue.fetch('id') == @issue.id }
    refute_nil record
    assert_tag_payload record, @issue.tags.map(&:name)
  end

  def test_xml_has_one_tag_array
    get :show, params: {id: @issue.id, format: 'xml', include: 'tags'}
    assert_response :success
    assert_select 'issue > tags', count: 1
    assert_select 'issue > tags > tag', count: @issue.tags.count
  end

  def test_tags_remain_opt_in
    get :show, params: {id: @issue.id, format: 'json'}
    assert_response :success
    refute JSON.parse(response.body).fetch('issue').key?('tags')
  end

  def test_disabled_tags_are_not_exposed
    Setting.plugin_additional_tags = Setting.plugin_additional_tags.merge(active_issue_tags: '0')
    get :show, params: {id: @issue.id, format: 'json', include: 'tags'}
    assert_response :success
    refute JSON.parse(response.body).fetch('issue').key?('tags')
  end

  def test_reader_without_tag_permission_cannot_read_or_write_tags
    original = @issue.tags.map(&:name)
    become_read_only_user
    get :show, params: {id: @issue.id, format: 'json', include: 'tags'}
    assert_response :success
    assert_tag_payload JSON.parse(response.body).fetch('issue'), []
    put :update, params: {id: @issue.id, format: 'json', issue: {tag_list: ['optimus-denied-tag']}}
    assert_response :forbidden
    assert_equal original.sort, @issue.reload.tags.map(&:name).sort
    refute AdditionalTag.exists?(name: 'optimus-denied-tag')
  end

  def test_issue_tag_edit_is_persisted_and_journaled
    original = @issue.tags.map(&:name)
    put :update, params: {id: @issue.id, format: 'json',
      issue: {tag_list: original + ['optimus-smoke-tag'], notes: 'Optimus tag fixture',
        custom_field_values: {'27' => '0', '31' => '0'}}}
    assert_response :success
    assert_includes @issue.reload.tags.map(&:name), 'optimus-smoke-tag'
    assert @issue.journals.order(id: :desc).first.details.exists?(prop_key: 'tag_list')
  end

  def test_issue_tag_filter_finds_existing_issue
    query = IssueQuery.new(name: 'Optimus tag fixture', project: @project)
    query.add_filter('status_id', '*', [])
    query.add_filter('tags', '=', [@issue.tags.first.name])
    assert_includes query.issues.map(&:id), @issue.id
  end
end

class OptimusProjectTagsApiSmokeTest < OptimusTagsSmokeTest
  tests ProjectsController

  def test_project_detail_preserves_aggregate_issue_tags
    expected = Issue.available_tags(project: @project).map(&:name)
    get :show, params: {id: @project.identifier, format: 'json', include: 'tags'}
    assert_response :success
    assert_tag_payload JSON.parse(response.body).fetch('project'), expected
  end

  def test_project_list_preserves_aggregate_issue_tags
    expected = Issue.available_tags(project: @project).map(&:name)
    get :index, params: {format: 'json', limit: 100, include: 'tags'}
    assert_response :success
    record = JSON.parse(response.body).fetch('projects').find { |project| project.fetch('id') == @project.id }
    refute_nil record
    assert_tag_payload record, expected
  end

  def test_project_aggregate_respects_tag_permission
    become_read_only_user
    get :show, params: {id: @project.identifier, format: 'json', include: 'tags'}
    assert_response :success
    assert_tag_payload JSON.parse(response.body).fetch('project'), []
  end
end

class OptimusWikiTagsSmokeTest < OptimusTagsSmokeTest
  tests WikiController

  def test_wiki_tag_display_and_edit
    page = WikiPage.joins(:tags).first!
    original = page.tags.map(&:name)
    get :show, params: {project_id: page.project.identifier, id: page.title}
    assert_response :success
    assert css_select('a').any? { |link| original.include?(link.text) }
    csrf_token = css_select('meta[name="csrf-token"]').first['content']
    put :update_tags, params: {project_id: page.project.identifier, id: page.title,
      authenticity_token: csrf_token, wiki_page: {tag_list: original + ['optimus-wiki-fixture']}}
    assert_response :redirect
    assert_includes page.reload.tags.map(&:name), 'optimus-wiki-fixture'
  end
end

class OptimusTagsAutocompleteSmokeTest < OptimusTagsSmokeTest
  tests AutoCompletesController

  def test_issue_tag_autocomplete
    name = @issue.tags.first.name
    get :issue_tags, params: {q: name}
    assert_response :success
    entries = JSON.parse(response.body)
    assert_includes entries.map { |entry| entry.fetch('text') }, name
  end
end

class OptimusTagListApiSmokeTest < OptimusTagsSmokeTest
  tests AdditionalTagsController

  setup do
    @admin = @user
    Setting.plugin_additional_tags = Setting.plugin_additional_tags.merge(active_issue_tags: '1')
    Setting.login_required = '0'
    Setting.display_subprojects_issues = '1'
    [Role.non_member, Role.anonymous].each do |role|
      role.update!(permissions: role.permissions - [:view_issue_tags])
    end

    @tag_role = Role.create!(name: 'Optimus tag list reader', permissions: %i[view_issues view_issue_tags],
      issues_visibility: 'default')
    @view_role = Role.create!(name: 'Optimus tag list viewer', permissions: [:view_issues],
      issues_visibility: 'default')
    @requester = User.new(login: 'optimus-tag-list', firstname: 'Optimus', lastname: 'TagList',
      mail: 'optimus-tag-list@example.invalid', status: User::STATUS_ACTIVE)
    @requester.password = @requester.password_confirmation = 'OptimusTagList_2026!'
    @requester.save!

    @parent = create_fixture_project('parent', roles: [@tag_role])
    @child_ok = create_fixture_project('child-ok', parent: @parent, roles: [@tag_role])
    @child_denied = create_fixture_project('child-denied', parent: @parent, roles: [@view_role])
    @denied = create_fixture_project('denied', roles: [@view_role], is_public: true)
    @private = create_fixture_project('private', roles: [])
    [@parent, @child_ok, @child_denied].each(&:reload)

    @tags = %w[shared parent-only priv-count child-only child-denied-only denied-only private-only].to_h do |name|
      [name, AdditionalTag.create!(name: "optimus-fixture-#{name}")]
    end
    create_fixture_issue(@parent, %w[shared parent-only priv-count])
    @private_issue = create_fixture_issue(@parent, %w[priv-count], is_private: true)
    create_fixture_issue(@child_ok, %w[shared child-only])
    create_fixture_issue(@child_denied, %w[shared child-denied-only])
    create_fixture_issue(@denied, %w[shared denied-only])
    create_fixture_issue(@private, %w[shared private-only])
  end

  def create_fixture_project(key, roles:, parent: nil, is_public: false)
    project = Project.new(name: "Optimus tag list #{key}", identifier: "optimus-tag-list-#{key}", is_public: is_public)
    project.enabled_module_names = %w[issue_tracking]
    project.trackers = Tracker.all.to_a
    project.save!
    project.set_parent!(parent) if parent
    Member.create!(project: project, user: @requester, roles: roles) if roles.any?
    project
  end

  def create_fixture_issue(project, tag_keys, is_private: false)
    tracker = project.trackers.first
    issue = Issue.new(project: project, tracker: tracker, author: @admin, subject: 'Optimus tag list issue',
      priority: IssuePriority.default || IssuePriority.first, status: tracker.default_status, is_private: is_private)
    issue.save!(validate: false)
    tag_keys.each { |key| AdditionalTagging.create!(tag: @tags.fetch(key), taggable: issue) }
    issue
  end

  def reset_identity
    @request.session.clear
    @request.env.delete('HTTP_X_REDMINE_API_KEY')
    User.current = User.anonymous
  end

  def sign_in_session(user)
    reset_identity
    @request.session[:user_id] = user.id
    @request.session[:tk] = user.generate_session_token
  end

  def sign_in_api_key(user)
    reset_identity
    @request.headers['X-Redmine-API-Key'] = user.api_key
  end

  def request_tags(params = {}, format = 'json')
    @controller = AdditionalTagsController.new
    get :index, params: {type: 'issue', format: format}.merge(params)
  end

  def assert_requested_as(user)
    assert_equal user.id, User.current.id
  end

  # Expected {tag name => [tag id, distinct issue count]} read from raw rows,
  # without Issue.available_tags, AdditionalTag.available_tags or the controller.
  def expected_issue_tags(user, scope_project_ids = nil)
    fresh_user = User.find(user.id)
    allowed_ids = Project.all.select { |project| fresh_user.allowed_to?(:view_issue_tags, project) }.map(&:id)
    allowed_ids &= scope_project_ids if scope_project_ids
    rows = AdditionalTagging.where(taggable_type: 'Issue').pluck(:tag_id, :taggable_id)
    issue_project_ids = Issue.where(id: rows.map(&:last)).pluck(:id, :project_id).to_h
    issue_ids_by_tag = Hash.new { |hash, key| hash[key] = Set.new }
    rows.each do |tag_id, issue_id|
      issue_ids_by_tag[tag_id] << issue_id if allowed_ids.include?(issue_project_ids[issue_id])
    end
    names = AdditionalTag.where(id: issue_ids_by_tag.keys).pluck(:id, :name).to_h
    issue_ids_by_tag.to_h { |tag_id, issue_ids| [names.fetch(tag_id), [tag_id, issue_ids.size]] }
  end

  def json_tags
    body = JSON.parse(response.body)
    assert_equal body.fetch('tags').size, body.fetch('total_count')
    assert_equal 'Issue', body.fetch('tag_type')
    body.fetch('tags').to_h { |tag| [tag.fetch('name'), [tag.fetch('id'), tag.fetch('count')]] }
  end

  def fixture_tags(actual)
    actual.select { |name, _| name.start_with?('optimus-fixture-') }.transform_keys { |name| name.delete_prefix('optimus-fixture-') }
      .transform_values(&:last)
  end

  def test_fixture_permissions
    user = User.find(@requester.id)
    assert user.allowed_to?(:view_issue_tags, @parent)
    assert user.allowed_to?(:view_issue_tags, @child_ok)
    refute user.allowed_to?(:view_issue_tags, @child_denied)
    refute user.allowed_to?(:view_issue_tags, @denied)
    refute user.allowed_to?(:view_issue_tags, @private)
    assert @denied.visible?(user)
    refute @private.visible?(user)
    refute @private_issue.visible?(user)
    assert Setting.display_subprojects_issues?
  end

  def test_search_matches_case_insensitively_with_scoped_counts_in_json_and_xml
    sign_in_api_key(@requester)
    expected = expected_issue_tags(@requester).select { |name, _| name.downcase.include?('fixture-') }
    request_tags({q: ' FiXtUrE- '})
    assert_response :success
    assert_requested_as @requester
    actual = json_tags
    assert_equal expected, actual
    assert_equal 2, fixture_tags(actual).fetch('shared')
    %w[child-denied-only denied-only private-only].each do |name|
      refute_includes actual.keys, "optimus-fixture-#{name}"
    end

    request_tags({q: ' FiXtUrE- '}, 'xml')
    assert_response :success
    assert_requested_as @requester
    doc = Nokogiri::XML(response.body)
    entries = doc.xpath('//tags/tag')
    assert_equal expected, entries.to_h { |tag| [tag['name'], [tag['id'].to_i, tag['count'].to_i]] }
    assert_equal expected.size, doc.root['total_count'].to_i
    assert_equal 'Issue', doc.root['tag_type']
  end

  def test_search_orders_by_scoped_count_then_name
    sign_in_api_key(@requester)
    expected = expected_issue_tags(@requester).select { |name, _| name.downcase.include?('optimus-fixture-') }
    request_tags({q: 'optimus-fixture-'})
    assert_response :success
    assert_equal expected, json_tags
    names = JSON.parse(response.body).fetch('tags').map { |tag| tag.fetch('name') }
    assert_equal expected.sort_by { |name, (_, count)| [-count, name] }.map(&:first), names
    assert_equal %w[priv-count shared child-only parent-only].map { |name| "optimus-fixture-#{name}" }, names
  end

  def test_search_intersects_project_selection_and_counts
    sign_in_api_key(@requester)
    scoped = expected_issue_tags(@requester, [@child_ok.id])
    request_tags({project_id: @child_ok.identifier, q: 'only'})
    assert_response :success
    actual = json_tags
    assert_equal scoped.select { |name, _| name.downcase.include?('only') }, actual
    assert_equal({'child-only' => 1}, fixture_tags(actual))
    refute_includes actual.keys, 'optimus-fixture-parent-only'
    refute_includes actual.keys, 'optimus-fixture-shared'

    request_tags({project_id: @child_ok.identifier, q: 'shared'})
    assert_response :success
    actual = json_tags
    assert_equal scoped.select { |name, _| name.downcase.include?('shared') }, actual
    assert_equal 1, fixture_tags(actual).fetch('shared')
  end

  def test_search_treats_like_characters_literally
    ['literal%mark', 'literal_mark', 'literal\\mark', 'literalXmark', 'literalmark'].each do |name|
      @tags[name] = AdditionalTag.create!(name: "optimus-fixture-#{name}")
    end
    create_fixture_issue(@parent, ['literal%mark', 'literal_mark', 'literal\\mark', 'literalXmark', 'literalmark'])
    sign_in_api_key(@requester)
    ['%', '_', '\\'].each do |query|
      expected = expected_issue_tags(@requester).select { |name, _| name.downcase.include?(query.downcase) }
      request_tags({q: query})
      assert_response :success
      assert_equal expected, json_tags
      actual_names = JSON.parse(response.body).fetch('tags').map { |tag| tag.fetch('name') }
      assert_includes actual_names, "optimus-fixture-literal#{query}mark"
      refute_includes actual_names, 'optimus-fixture-literalXmark'
    end
  end

  def test_blank_search_preserves_plain_list_and_name_order
    sign_in_api_key(@requester)
    expected = expected_issue_tags(@requester)
    request_tags
    assert_response :success
    assert_equal expected, json_tags
    plain_names = JSON.parse(response.body).fetch('tags').map { |tag| tag.fetch('name') }
    fixture_names = plain_names.select { |name| name.start_with?('optimus-fixture-') }
    assert_equal fixture_names.sort, fixture_names

    ['', " \t "].each do |query|
      request_tags({q: query})
      assert_response :success
      assert_equal expected, json_tags
      names = JSON.parse(response.body).fetch('tags').map { |tag| tag.fetch('name') }
      assert_equal plain_names, names
    end
  end

  def test_non_admin_api_key_lists_scoped_tags_in_json_and_xml
    sign_in_api_key(@requester)
    request_tags
    assert_response :success
    assert_requested_as @requester
    expected = expected_issue_tags(@requester)
    assert_equal expected, json_tags
    refute_includes expected.keys, 'optimus-fixture-denied-only'

    request_tags({}, 'xml')
    assert_response :success
    assert_requested_as @requester
    assert_select 'tags > tag', count: expected.size
    expected.each do |name, (id, count)|
      assert_select "tags > tag[name='#{name}'][id='#{id}'][count='#{count}']", count: 1
    end
  end

  def test_anonymous_api_requests_are_unauthorized
    reset_identity
    assert @denied.is_public?
    %w[json xml].each do |format|
      request_tags({}, format)
      assert_response :unauthorized
      assert_equal User.anonymous.id, User.current.id
      refute_includes response.body, 'optimus-fixture'
    end
  end

  def test_tags_from_permitted_projects_are_unioned_once
    sign_in_api_key(@requester)
    request_tags
    assert_response :success
    actual = json_tags
    assert_equal expected_issue_tags(@requester), actual
    assert_equal %w[child-only parent-only priv-count shared], fixture_tags(actual).keys.sort
    assert_equal actual.size, actual.keys.uniq.size
  end

  def test_private_issue_contributes_to_scoped_count
    sign_in_api_key(@requester)
    request_tags
    assert_response :success
    actual = json_tags
    assert_equal expected_issue_tags(@requester), actual
    assert_equal 2, fixture_tags(actual).fetch('priv-count')
  end

  def test_user_without_tag_permission_gets_empty_list
    @tag_role.update!(permissions: [:view_issues])
    sign_in_api_key(@requester)
    request_tags
    assert_response :success
    assert_empty expected_issue_tags(@requester)
    assert_equal({}, json_tags)
    assert_equal 0, JSON.parse(response.body).fetch('total_count')
  end

  def test_shared_tag_count_excludes_denied_projects
    sign_in_api_key(@requester)
    request_tags
    assert_response :success
    actual = json_tags
    assert_equal expected_issue_tags(@requester), actual
    assert_equal 5, AdditionalTagging.where(tag_id: @tags.fetch('shared').id, taggable_type: 'Issue').count
    assert_equal 2, fixture_tags(actual).fetch('shared')
  end

  def test_project_selected_by_identifier_narrows_list
    sign_in_api_key(@requester)
    expected = expected_issue_tags(@requester, [@child_ok.id])
    request_tags({project_id: @child_ok.identifier})
    assert_response :success
    actual = json_tags
    assert_equal expected, actual
    assert_equal({'shared' => 1, 'child-only' => 1}, fixture_tags(actual))

    request_tags({project_id: @child_ok.id.to_s})
    assert_response :success
    assert_equal expected, json_tags
  end

  def test_visible_project_without_tag_permission_gets_empty_list
    sign_in_api_key(@requester)
    assert_empty expected_issue_tags(@requester, [@denied.id])
    request_tags({project_id: @denied.identifier})
    assert_response :success
    assert_equal({}, json_tags)
    assert_equal 0, JSON.parse(response.body).fetch('total_count')
  end

  def test_selected_project_includes_permitted_child_and_excludes_denied_child
    sign_in_api_key(@requester)
    expected = expected_issue_tags(@requester, [@parent.id, @child_ok.id, @child_denied.id])
    request_tags({project_id: @parent.identifier})
    assert_response :success
    actual = json_tags
    assert_equal expected, actual
    assert_equal({'shared' => 2, 'parent-only' => 1, 'priv-count' => 2, 'child-only' => 1}, fixture_tags(actual))
  end

  def test_missing_project_returns_not_found
    sign_in_api_key(@requester)
    request_tags({project_id: 'optimus-tag-list-missing'})
    assert_response :not_found
    refute_includes response.body, 'optimus-fixture'
  end

  def test_invisible_project_returns_not_found
    sign_in_api_key(@requester)
    refute @private.visible?(User.find(@requester.id))
    request_tags({project_id: @private.identifier})
    assert_response :not_found
    refute_includes response.body, 'optimus-fixture'
  end

  def test_admin_list_without_project_is_unchanged
    sign_in_api_key(@admin)
    request_tags
    assert_response :success
    assert_requested_as @admin
    actual = json_tags
    assert_equal expected_issue_tags(@admin), actual
    assert_includes actual.keys, 'optimus-fixture-private-only'
  end

  def test_non_admin_html_index_is_forbidden
    sign_in_session(@requester)
    request_tags({}, nil)
    assert_response :forbidden
    assert_requested_as @requester
    request_tags({type: nil}, nil)
    assert_response :forbidden
  end

  def test_admin_html_index_redirects_to_tag_management
    sign_in_session(@admin)
    request_tags({}, nil)
    assert_requested_as @admin
    assert_redirected_to controller: 'settings', action: 'plugin', id: 'additional_tags', tab: 'manage_tags'
  end

  def test_listing_does_not_grant_edit_or_merge
    sign_in_api_key(@requester)
    request_tags
    assert_response :success

    sign_in_session(@requester)
    shared = @tags.fetch('shared')
    other = @tags.fetch('denied-only')
    tag_ids = AdditionalTag.order(:id).pluck(:id)
    tagging_rows = AdditionalTagging.order(:id).pluck(:id, :tag_id, :taggable_id)

    @controller = AdditionalTagsController.new
    get :edit, params: {id: shared.id}
    assert_response :forbidden

    @controller = AdditionalTagsController.new
    post :merge, params: {ids: [shared.id, other.id], tag: {name: shared.name}}
    assert_response :forbidden
    assert_requested_as @requester

    assert_equal tag_ids, AdditionalTag.order(:id).pluck(:id)
    assert_equal tagging_rows, AdditionalTagging.order(:id).pluck(:id, :tag_id, :taggable_id)
  end
end
