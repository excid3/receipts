require "spec_helper"

describe Receipts do
  it "lets you create a new receipt" do
    expect(Receipts::Receipt.new(
      id: 1,
      product: "GoRails",
      company: {
        name: "One Month, Inc.",
        address: "37 Great Jones\nFloor 2\nNew York City, NY 10012",
        email: "teachers@onemonth.com"
      },
      line_items: [
        ["Product", "GoRails"]
      ]
    ).class.name).to eq("Receipts::Receipt")
  end
end
