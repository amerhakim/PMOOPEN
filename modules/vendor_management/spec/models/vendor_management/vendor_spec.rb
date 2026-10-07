require_relative "../../spec_helper"

RSpec.describe VendorManagement::Vendor do
  it "requires a name" do
    vendor = described_class.new(status: "active")
    expect(vendor).not_to be_valid
    expect(vendor.errors[:name]).to be_present
  end

  it "defaults are valid with just a name" do
    vendor = described_class.new(name: "Acme Supplies", status: "active")
    expect(vendor).to be_valid
  end

  it "rejects an unknown status" do
    vendor = described_class.new(name: "Acme Supplies", status: "bogus")
    expect(vendor).not_to be_valid
    expect(vendor.errors[:status]).to be_present
  end

  it "stores and reads back multiple categories" do
    vendor = described_class.create!(name: "Acme Supplies", status: "active", category_list: %w[Hardware Software])
    expect(vendor.reload.category_list).to contain_exactly("Hardware", "Software")
  end

  it "ignores categories outside the known list" do
    vendor = described_class.create!(name: "Acme Supplies", status: "active", category_list: ["Hardware", "Not A Category"])
    expect(vendor.reload.category_list).to contain_exactly("Hardware")
  end

  it "replaces the category list on update rather than accumulating" do
    vendor = described_class.create!(name: "Acme Supplies", status: "active", category_list: ["Hardware"])
    vendor.update!(category_list: ["Service"])
    expect(vendor.reload.category_list).to contain_exactly("Service")
  end
end
