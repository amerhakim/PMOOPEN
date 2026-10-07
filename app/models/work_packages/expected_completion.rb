# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

# Purely date-based "expected completion" percentage: given today's date and
# a work package's date range, how far through that range are we, regardless
# of how much work has actually been reported done. This is deliberately
# unrelated to +done_ratio+/percentageDone (which reflects actual, manually
# reported progress) -- it answers "if this task were exactly on schedule,
# what percentage of it should be done by now".
#
# For work packages with children (parent/summary tasks and, by the same
# logic, the project as a whole via its top-level work packages),
# derived_start_date/derived_due_date -- the min/max date across all
# descendants -- are used instead of the work package's own start_date/
# due_date, so the percentage always reflects the full span of the subtree
# regardless of whether the parent happens to be manually or automatically
# scheduled. Leaf work packages have no descendants, so derived_start_date/
# derived_due_date naturally fall back to nil and we use their own dates.
module WorkPackages::ExpectedCompletion
  # Returns an integer 0..100, or nil if there isn't enough date information
  # (no start and/or due date anywhere in the relevant range) to compute it.
  def expected_completion
    start = derived_start_date || start_date
    due = derived_due_date || due_date

    return nil if start.nil? || due.nil?

    today = Date.current

    return 0 if today < start
    return 100 if today >= due

    ((today - start).to_f / (due - start).to_f * 100).round
  end
end
