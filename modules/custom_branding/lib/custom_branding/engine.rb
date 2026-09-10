module CustomBranding
  class Engine < ::Rails::Engine
    include OpenProject::Plugins::ActsAsOpEngine

    register "custom_branding",
             author_url: "https://www.openproject.org",
             bundled: true do
      menu :admin_menu,
           :custom_branding,
           { controller: "/custom_branding", action: :show },
           if: ->(*) { User.current.admin? },
           caption: :label_custom_branding,
           icon: "paintbrush"
    end

    # OpenProject::Hook isn't loaded yet at gem-require time (Bundler.require
    # runs before core's own initializers) -- require the hook listener
    # later, once the app is actually booting. require_relative is
    # idempotent by path, so this only runs the file's class body once even
    # though to_prepare fires on every dev reload.
    config.to_prepare do
      require_relative "hooks"

      # Superseded by this module's own admin page -- remove the old,
      # Enterprise-gated "Design" entry so admins aren't left with two
      # branding entry points, one of which is locked. Standard plugin
      # technique (Redmine::MenuManager.map queues a builder block that
      # runs on every menu render; to_prepare guarantees ours runs after
      # core's own config/initializers/menus.rb has already pushed
      # :custom_style, so there's something there to delete). Not a core
      # file edit -- core still registers the item, this just removes it
      # from the rendered menu afterwards.
      Redmine::MenuManager.map(:admin_menu) { |mapper| mapper.delete(:custom_style) }
    end
  end
end
