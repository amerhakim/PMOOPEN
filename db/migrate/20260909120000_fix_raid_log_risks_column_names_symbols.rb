class FixRaidLogRisksColumnNamesSymbols < ActiveRecord::Migration[8.1]
  # 20260909100000 wrote column_names via update_column with a plain
  # string array ("id", "cf_23", ...) instead of going through Query's
  # own column_names= setter, which always converts to symbols before
  # write_attribute. Query#columns (used by `rails runner`/console
  # checks) happens to `.to_sym` each name before matching, so it looked
  # fine there -- but Query#valid_column_subset! (run on every API GET,
  # via QueriesAPI's `@query.valid_subset!`) does a raw
  # `column_names &= available_names` with no such coercion. String &
  # Symbol arrays never intersect, so every one of our columns was wiped
  # to [] on each request, silently falling back to
  # Setting.work_package_list_default_columns (id/subject/type/status/
  # assignee/priority) -- exactly what showed up live despite the DB
  # holding the right data the whole time. Not caught by the earlier
  # rails-runner check because that path never calls valid_subset!.
  def up
    Query.where(name: "Risks").find_each do |query|
      query.update_column(:column_names, query.column_names.map(&:to_sym))
    end
  end

  def down
    Query.where(name: "Risks").find_each do |query|
      query.update_column(:column_names, query.column_names.map(&:to_s))
    end
  end
end
