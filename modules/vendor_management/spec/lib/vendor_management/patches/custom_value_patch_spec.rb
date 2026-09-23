require_relative "../../../spec_helper"

RSpec.describe "VendorManagement::Patches::CustomValuePatch" do
  let(:custom_field) { create(:project_custom_field, name: "O&D", field_format: "string") }
  let(:original_project) { create(:project) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }

  let!(:matching_po) do
    VendorManagement::PurchaseOrder.create!(project: original_project, vendor:, o_and_d: "OD-123")
  end
  let!(:non_matching_po) do
    VendorManagement::PurchaseOrder.create!(project: original_project, vendor:, o_and_d: "OD-999")
  end

  it "moves purchase orders with a matching O&D into a project once its O&D custom field value is set" do
    custom_field
    new_project = create(:project)

    new_project.custom_field_values = { custom_field.id => "OD-123" }
    new_project.save!

    expect(matching_po.reload.project_id).to eq(new_project.id)
    expect(non_matching_po.reload.project_id).to eq(original_project.id)
  end

  it "does nothing for a custom field on Project that isn't named O&D" do
    other_field = create(:project_custom_field, name: "Client", field_format: "string")
    new_project = create(:project)

    new_project.custom_field_values = { other_field.id => "OD-123" }
    new_project.save!

    expect(matching_po.reload.project_id).to eq(original_project.id)
  end
end
