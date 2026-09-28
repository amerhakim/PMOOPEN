require_relative "../../spec_helper"

RSpec.describe VendorManagement::PoTemplate do
  describe "#layout" do
    it "falls back to DEFAULT_LAYOUT when layout_json is blank" do
      template = described_class.current
      template.update!(layout_json: nil)

      expect(template.reload.layout).to eq(VendorManagement::PoTemplate::DEFAULT_LAYOUT)
    end

    it "falls back to DEFAULT_LAYOUT when layout_json isn't valid JSON" do
      template = described_class.current
      template.update_column(:layout_json, "not json")

      expect(template.reload.layout).to eq(VendorManagement::PoTemplate::DEFAULT_LAYOUT)
    end

    it "falls back to DEFAULT_LAYOUT when a block id is missing or unknown, never handing PurchaseOrderPdf something it can't render" do
      template = described_class.current

      missing_block = VendorManagement::PoTemplate::DEFAULT_LAYOUT.reject { |b| b["id"] == "footer" }
      template.update!(layout: missing_block)
      expect(template.reload.layout).to eq(VendorManagement::PoTemplate::DEFAULT_LAYOUT)

      unknown_block = VendorManagement::PoTemplate::DEFAULT_LAYOUT.map(&:dup)
      unknown_block.first["id"] = "not_a_real_block"
      template.update!(layout: unknown_block)
      expect(template.reload.layout).to eq(VendorManagement::PoTemplate::DEFAULT_LAYOUT)
    end

    it "keeps a valid custom layout as-is" do
      template = described_class.current
      custom_layout = VendorManagement::PoTemplate::DEFAULT_LAYOUT.map(&:dup)
      custom_layout.find { |b| b["id"] == "logo" }["x"] = 200
      template.update!(layout: custom_layout)

      expect(template.reload.layout.find { |b| b["id"] == "logo" }["x"]).to eq(200)
    end
  end
end
