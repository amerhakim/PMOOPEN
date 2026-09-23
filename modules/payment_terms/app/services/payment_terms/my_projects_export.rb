require "caxlsx"

module PaymentTerms
  # Mirrors the on-screen /my/payment_terms report exactly -- same
  # columns, same project grouping -- but always the full role-scoped
  # dataset, ignoring any text filters currently applied on screen (same
  # behavior as VendorManagement::VendorExport, which also exports the
  # full list regardless of the page's own filter state).
  class MyProjectsExport
    COLUMNS = [
      "S/N", "Project", "O&D", "Account Manager", "Project Manager",
      "Payment Terms", "Value (QAR)", "Invoiced", "Expected Invoice Date",
      "Collected", "Invoice Number", "Invoice Date", "Comments"
    ].freeze

    def initialize(payments_by_project:, o_and_ds:, account_managers:, project_managers:)
      @payments_by_project = payments_by_project
      @o_and_ds = o_and_ds
      @account_managers = account_managers
      @project_managers = project_managers
    end

    def call
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Invoicing") do |sheet|
        sheet.add_row(COLUMNS)

        @payments_by_project.each_with_index do |(project, payments), index|
          payments.each do |payment|
            sheet.add_row([
              index + 1,
              project.name,
              @o_and_ds[project.id],
              @account_managers[project.id],
              Array(@project_managers[project.id]).join(", "),
              payment.description,
              payment.value,
              payment.invoiced? ? "Yes" : "No",
              payment.expected_invoice_date,
              payment.collected? ? "Yes" : "No",
              payment.invoice_number,
              payment.invoice_date,
              payment.comments
            ])
          end
        end
      end

      package.to_stream.read
    end
  end
end
