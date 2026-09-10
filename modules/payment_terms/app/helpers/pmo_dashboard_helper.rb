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

  def pmo_currency(amount)
    amount = amount.to_f
    if amount >= 1_000_000
      "QAR #{'%.1f' % (amount / 1_000_000)}M"
    elsif amount >= 1_000
      "QAR #{(amount / 1_000).round}K"
    else
      "QAR #{amount.round}"
    end
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
