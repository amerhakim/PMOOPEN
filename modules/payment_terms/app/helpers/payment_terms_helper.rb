module PaymentTermsHelper
  # Account Manager is its own project attribute (client-relationship
  # owner), deliberately separate from whoever holds the Project Manager
  # role -- see db/migrate/20260908090000_create_account_manager_project_custom_field.rb.
  def payment_terms_account_manager(project)
    field = ProjectCustomField.find_by(name: "Account Manager")
    return nil unless field

    project.custom_value_for(field)&.value
  end

  # Whoever holds the "Project Manager" role on this project (via a real
  # membership, not a project attribute) -- joins names with ", " on the
  # rare case a project has more than one.
  def payment_terms_project_manager(project)
    names = project.memberships
                    .joins(:roles)
                    .where(roles: { name: "Project Manager" })
                    .distinct
                    .map { |member| member.principal.name }

    names.join(", ").presence
  end

  # Green once collected, red once invoiced but still not collected,
  # left at the default text color while neither has happened yet. Uses
  # Primer's own color-fg-success/color-fg-danger utility classes (same
  # tokens Primer::Beta::Text's color: :success/:danger map to) rather
  # than hardcoded hex, so this adapts correctly under dark mode / high
  # contrast themes instead of a fixed color.
  def payment_row_color_class(payment)
    if payment.cancelled?
      "color-fg-muted"
    elsif payment.collected?
      "color-fg-success"
    elsif payment.invoiced?
      "color-fg-danger"
    else
      ""
    end
  end

  # Full "QAR 1.23M"/"QAR 456K" label used on the analytics dashboard's KPI
  # cards and legends -- always at least a whole QAR figure, never raw
  # cents, so it stays readable next to a dozen other numbers on the page.
  def payment_terms_compact_currency(value, currency = (@analytics_currency || "QAR"))
    v = value.to_f
    return "#{currency} #{format('%.2f', v / 1_000_000)}M" if v.abs >= 1_000_000
    return "#{currency} #{(v / 1_000).round}K" if v.abs >= 1_000

    payment_terms_money(v, currency)
  end

  # "QAR 1,234.00" / "-SAR 971,000.00" -- every amount on every payment
  # screen goes through here so the unit always follows the contract
  # line's own currency instead of a hardcoded QAR.
  def payment_terms_money(amount, currency = "QAR")
    number_to_currency(amount, unit: "#{currency} ", format: "%u%n", negative_format: "-%u%n")
  end

  # Amount for the dense Project Invoices table: QAR (the default
  # currency) is shown as a bare number so large values fit the column;
  # any other currency keeps its prefix so SAR rows stay unambiguous.
  def payment_terms_amount(amount, currency = "QAR")
    return payment_terms_money(amount, currency) unless currency == "QAR"

    number_to_currency(amount, unit: "", format: "%n", negative_format: "-%n")
  end

  # Same scale as payment_terms_compact_currency but bare (no "QAR "
  # prefix, blank for zero) -- for the small value labels stacked directly
  # on top of a chart bar, where the unit is already implied by the chart.
  def payment_terms_chart_short(value)
    v = value.to_f
    return "" if v <= 0
    return "#{format('%.1f', v / 1_000_000)}M" if v >= 1_000_000

    "#{(v / 1_000).round}K"
  end

  def payment_terms_pct(value, total)
    return "0.0%" if total.to_f.zero?

    "#{format('%.1f', value.to_f / total.to_f * 100)}%"
  end

  # Matches the approved mockup's gauge thresholds exactly: on track once
  # 75%+ of what's due to date has actually been issued, a watch zone from
  # 50-74%, behind below that.
  def payment_terms_gauge_color(pct)
    return "#16a34a" if pct >= 75
    return "#d97706" if pct >= 50

    "#e11d48"
  end

  # Needle tip for the semicircle gauge (center 100,100 radius r) -- same
  # angle convention as the approved mockup: 0% points left (180deg), 100%
  # points right (0deg), sweeping up through the top at 50%.
  def payment_terms_gauge_needle(pct, r = 64)
    rad = (180 - (1.8 * pct)) * Math::PI / 180
    { x: 100 + (r * Math.cos(rad)), y: 100 - (r * Math.sin(rad)) }
  end
end

