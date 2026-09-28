module CustomBranding
  class Setting < ApplicationRecord
    self.table_name = "custom_brandings"

    mount_uploader :logo, OpenProject::Configuration.file_uploader

    COLOR_FIELDS = %w[
      header_bg_color
      main_menu_bg_color
      main_menu_bg_selected_background
      accent_color
      primary_button_color
    ].freeze

    HEX_COLOR = /\A#[0-9A-Fa-f]{6}\z/

    validates(*COLOR_FIELDS.map(&:to_sym), format: { with: HEX_COLOR }, allow_blank: true)

    class << self
      def current
        order(created_at: :desc).first
      end

      # Plain WCAG-ish relative-luminance check -- picks readable text
      # (near-black or white) for a given background hex. Same idea core
      # uses for its own (gated) design colors, reimplemented independently.
      def contrasting_font_color(hexcode)
        return "#FFFFFF" if hexcode.blank?

        r, g, b = hexcode.delete("#").scan(/../).map { |c| c.to_i(16) }
        luminance = ((0.299 * r) + (0.587 * g) + (0.114 * b)) / 255.0
        luminance > 0.6 ? "#1A1A1A" : "#FFFFFF"
      end
    end

    def digest
      updated_at.to_i
    end
  end
end
