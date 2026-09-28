module Impersonation
  class Hooks < ::OpenProject::Hook::ViewListener
    # A persistent banner across every page while impersonating, so it is
    # never ambiguous which account is actually acting -- rendered via
    # this hook rather than editing layouts/base.html.erb directly.
    render_on :view_layouts_base_top_menu,
              partial: "impersonations/banner"
  end
end
