module MsProjectImport
  class Engine < ::Rails::Engine
    include OpenProject::Plugins::ActsAsOpEngine

    register "ms_project_import",
             author_url: "https://www.openproject.org",
             bundled: true do
      project_module :ms_project_import do
        permission :import_ms_project,
                   { ms_project_imports: %i[new create show] },
                   permissible_on: :project
      end

      menu :project_menu,
           :ms_project_import,
           { controller: "/ms_project_imports", action: "new" },
           if: ->(project) { project.module_enabled?(:ms_project_import) },
           after: :work_packages,
           caption: :label_ms_project_import,
           icon: "upload"
    end
  end
end
