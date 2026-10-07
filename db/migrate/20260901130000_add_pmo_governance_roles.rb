class AddPmoGovernanceRoles < ActiveRecord::Migration[8.1]
  ROLES = [
    {
      name: "PMO Director",
      type: "ProjectRole",
      position: 12,
      permissions: %w[
        archive_project comment_news edit_project edit_project_attributes
        edit_project_phases export_projects manage_members manage_public_queries
        manage_types search_project select_custom_fields select_project_custom_fields
        select_project_modules select_project_phases share_calendars show_board_views
        show_github_content view_calendar view_file_links view_members view_messages
        view_news view_project view_project_activity view_project_attributes
        view_project_phases view_wiki_pages view_work_packages
      ]
    },
    {
      name: "PMO Director (Global)",
      type: "GlobalRole",
      position: 13,
      permissions: %w[
        add_portfolios add_programs manage_public_project_queries view_all_principals
      ]
    },
    {
      name: "Portfolio Manager",
      type: "ProjectRole",
      position: 14,
      permissions: %w[
        add_subprojects comment_news edit_project edit_project_attributes
        edit_project_phases edit_work_packages export_projects manage_members
        manage_versions search_project share_calendars show_board_views
        show_github_content view_budgets view_calendar view_file_links view_members
        view_messages view_news view_project view_project_activity
        view_project_attributes view_project_phases view_wiki_pages view_work_packages
      ]
    },
    {
      name: "Program Manager",
      type: "ProjectRole",
      position: 15,
      permissions: %w[
        add_subprojects comment_news edit_budgets edit_project edit_project_phases
        edit_work_packages export_projects manage_categories manage_members
        manage_versions manage_work_package_relations search_project share_calendars
        show_board_views show_github_content view_budgets view_calendar view_file_links
        view_members view_messages view_news view_project view_project_activity
        view_project_attributes view_project_phases view_wiki_pages view_work_packages
      ]
    },
    {
      name: "Project Manager",
      type: "ProjectRole",
      position: 16,
      permissions: %w[
        add_work_packages assign_versions change_work_package_status comment_news
        delete_work_packages edit_budgets edit_project edit_project_attributes
        edit_project_phases edit_time_entries edit_work_packages export_projects
        export_work_packages log_costs log_time manage_categories manage_members
        manage_subtasks manage_versions manage_work_package_relations move_work_packages
        save_queries search_project share_calendars show_board_views show_github_content
        view_budgets view_calendar view_file_links view_members view_messages view_news
        view_project view_project_activity view_project_attributes view_project_phases
        view_time_entries view_wiki_pages view_work_packages
      ]
    },
    {
      name: "Functional Manager",
      type: "ProjectRole",
      position: 17,
      permissions: %w[
        add_work_packages allocate_user_resources assign_users_to_generic_allocations
        comment_news edit_work_packages manage_public_queries
        manage_public_resource_planners manage_team_planner save_queries search_project
        share_calendars show_board_views show_github_content view_calendar
        view_file_links view_members view_messages view_news view_project
        view_project_activity view_project_attributes view_project_phases
        view_resource_planners view_team_planner view_wiki_pages view_work_packages
      ]
    },
    {
      name: "Technical Team Member",
      type: "ProjectRole",
      position: 18,
      permissions: %w[
        add_work_package_attachments add_work_package_comments add_work_packages
        add_work_package_watchers change_work_package_status comment_news
        edit_own_time_entries edit_own_work_package_comments edit_work_packages
        log_own_time search_project share_calendars show_board_views show_github_content
        view_calendar view_file_links view_members view_messages view_news
        view_own_time_entries view_project view_project_activity view_project_attributes
        view_project_phases view_wiki_pages view_work_packages
      ]
    },
    {
      name: "Executive / Sponsor",
      type: "ProjectRole",
      position: 19,
      permissions: %w[
        comment_news export_projects export_work_packages search_project
        share_calendars show_board_views show_github_content view_budgets view_calendar
        view_cost_entries view_file_links view_members view_messages view_news
        view_project view_project_activity view_project_attributes view_project_phases
        view_wiki_pages view_work_packages
      ]
    }
  ].freeze

  def up
    ROLES.each do |role_data|
      next if Role.exists?(name: role_data[:name])

      klass = role_data[:type].constantize
      role = klass.create!(
        name: role_data[:name],
        position: role_data[:position],
        builtin: Role::NON_BUILTIN
      )
      role.permissions = role_data[:permissions]
      role.save!
    end
  end

  def down
    Role.where(name: ROLES.map { |r| r[:name] }).destroy_all
  end
end
