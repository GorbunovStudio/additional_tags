module AdditionalTags
  module OptimusApiTags
    RECORDS = {
      'issues/index' => 'issue', 'issues/show' => '@issue',
      'projects/index' => 'project', 'projects/show' => '@project'
    }.freeze

    def call(template, source = nil)
      compiled = super
      record = RECORDS[template.virtual_path]
      return compiled unless record

      compiled.sub(/^(\s*)api\.created_on/) do
        "#{Regexp.last_match(1)}render_api_optimus_tags(#{record}, api)\n#{Regexp.last_match(0)}"
      end
    end
  end

  module OptimusApiTagsHelper
    def render_api_optimus_tags(record, api)
      return unless AdditionalTags.setting?(:active_issue_tags) && include_in_api_response?('tags')

      tags = if record.is_a?(Issue)
               User.current.allowed_to?(:view_issue_tags, record.project) ? record.tags : []
             else
               Issue.available_tags(project: record)
             end
      api.array :tags do
        tags.each { |tag| api.tag(id: tag.id, name: tag.name) }
      end
    end
  end
end