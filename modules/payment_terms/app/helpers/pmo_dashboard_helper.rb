module PmoDashboardHelper
  PALETTE = ["#4f46e5", "#06b6d4", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6"].freeze

  def pmo_color_for(project_id)
    PALETTE[project_id % PALETTE.size]
  end

  def pmo_variance(expected, actual)
    return nil if expected.nil? || actual.nil?

    variance = actual - expected
    {
      value: variance.abs,
      color: variance >= 0 ? "#10b981" : "#ef4444",
      icon: variance >= 0 ? "&uarr;" : "&darr;"
    }
  end

  def pmo_currency(amount, currency = "QAR")
    amount = amount.to_f
    sign = amount.negative? ? "-" : ""
    magnitude = amount.abs
    if magnitude >= 1_000_000
      "#{sign}#{currency} #{'%.1f' % (magnitude / 1_000_000)}M"
    elsif magnitude >= 1_000
      "#{sign}#{currency} #{(magnitude / 1_000).round}K"
    else
      "#{sign}#{currency} #{magnitude.round}"
    end
  end

  HEALTH_COLORS = {
    "archived" => "#64748b",
    "on_track" => "#22a06b",
    "at_risk" => "#f5b73b",
    "finished" => "#3b82f6",
    "off_track" => "#ef4444",
    "none" => "#cbd5e1"
  }.freeze
  DEPARTMENT_COLORS = ["#3b82f6", "#2cc7c0", "#8b8cf5", "#f59e42", "#5bb8f5", "#ec6c9a", "#94a3b8"].freeze

  # Maps OpenProject's native project status onto the dashboard buckets;
  # not_started, discontinued and "no status set" all land in "none".
  def pmo_health_key(project)
    case project.status_code
    when "on_track", "at_risk", "off_track", "finished" then project.status_code
    else "none"
    end
  end

  def pmo_health_color(key)
    HEALTH_COLORS.fetch(key)
  end

  KPI_ICON_PATHS = {
    folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    runner: '<circle cx="15" cy="4.5" r="1.8"/><path d="M14 8l-3 5 3.5 3-1 5M14 8l4 3 3-1M13 9l-4 1-2 3M11 13l-4 4H4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    alert: '<path d="M12 3.5 2.5 20h19z"/><path d="M12 10v4.5M12 17.5h.01"/>',
    check: '<circle cx="12" cy="12" r="9"/><path d="m8 12.5 3 3 5-6"/>',
    archive: '<rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8M10 12h4"/>'
  }.freeze

  def pmo_kpi_icon(name)
    (%(<svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.8" ) +
      %(stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">#{KPI_ICON_PATHS.fetch(name)}</svg>)).html_safe
  end

  # Donut/ring geometry: one stroked circle per non-empty entry, positioned
  # with stroke-dasharray/offset, plus the label anchor at the arc midpoint.
  def pmo_donut_segments(entries, radius:, center:)
    total = entries.sum { |e| e[:count] }
    return [] if total.zero?

    circumference = 2 * Math::PI * radius
    visible = entries.select { |e| e[:count].positive? }
    travelled = 0.0
    visible.map do |entry|
      fraction = entry[:count].to_f / total
      length = fraction * circumference
      mid = ((travelled + length / 2) / circumference * 2 * Math::PI) - Math::PI / 2
      segment = entry.merge(
        fraction:,
        percent: (fraction * 100).round,
        dash: [length - (visible.size > 1 ? 1.5 : 0), 0.1].max.round(2),
        gap: (circumference - length).round(2),
        offset: -travelled.round(2),
        label_x: (center + radius * Math.cos(mid)).round(1),
        label_y: (center + radius * Math.sin(mid)).round(1)
      )
      travelled += length
      segment
    end
  end

  def pmo_milestone_plan_path(project, work_package_id)
    query_props = {
      c: %w[id subject startDate dueDate percentageDone],
      hi: true,
      g: "",
      t: "id:asc",
      f: [{ n: "parent", o: "=", v: [work_package_id.to_s] }]
    }
    project_gantt_index_path(project, query_props: query_props.to_json)
  end

  def pmo_risks_issues_path(project)
    risk_type = Type.find_by(name: "Risk")
    issue_type = Type.find_by(name: "Issue")
    type_ids = [risk_type, issue_type].compact.map { |t| t.id.to_s }
    return project_work_packages_path(project) if type_ids.empty?

    query_props = { c: %w[id type subject status], t: "id:desc", f: [{ n: "type", o: "=", v: type_ids }] }
    project_work_packages_path(project, query_props: query_props.to_json)
  end
end


