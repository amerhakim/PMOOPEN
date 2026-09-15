module CustomBranding
  # Renders our own CSS-variable overrides into the page <head>, using the
  # existing unconditional view_layouts_base_html_meta hook point (the same
  # one core uses for its own, Enterprise-gated custom style output further
  # down that template) -- entirely independent of CustomStyle/DesignColor/
  # EnterpriseToken.
  class Hooks < ::OpenProject::Hook::ViewListener
    render_on :view_layouts_base_html_meta, partial: "custom_branding/inline_css"
  end
end
