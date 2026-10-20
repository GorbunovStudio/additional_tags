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