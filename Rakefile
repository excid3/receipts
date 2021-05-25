require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "open-uri"

RSpec::Core::RakeTask.new('spec')

# If you want to make this the default task
task :default => :spec
task :test => :spec

task :console do
  exec "irb -r receipts -I ./lib"
end

task :receipt do
  require "./lib/receipts"

  Receipts::Receipt.new(
    id: "123",
    subheading: "RECEIPT FOR CHARGE #1",
    product: "GoRails",
    company: {
      name: "GoRails, LLC",
      address: "123 Fake Street\nNew York City, NY 10012",
      email: "support@example.com",
      logo: URI.open("https://www.ruby-lang.org/images/header-ruby-logo@2x.png")
    },
    line_items: [
      ["Date",           Time.now.to_s],
      ["Account Billed", "Example User (user@example.com)"],
      ["Product",        "GoRails"],
      ["Amount",         "$19.00"],
      ["Charged to",     "Visa (**** **** **** 1234)"],
      ["Transaction ID", "123456"]
    ],
  ).render_file "examples/receipt.pdf"
end

task :invoice do
  require "./lib/receipts"

  Receipts::Invoice.new(
    id: "123",
    issue_date: Date.today,
    due_date: Date.today + 30,
    status: "<b><color rgb='#5eba7d'>PAID</color></b>",
    bill_to: [
      "GoRails, LLC",
      "Address",
      "City, State Zipcode",
      nil,
      "mail@example.com",
    ],
    company: {
      name: "GoRails, LLC",
      address: "123 Fake Street\nNew York City, NY 10012",
      email: "support@example.com",
      #logo: Rails.root.join("app/assets/images/gorails.png")
      #logo: File.expand_path("./examples/gorails.png")
      logo: File.open("./examples/gorails.png")
    },
    line_items: [
      ["<b>Item</b>", "<b>Unit Cost</b>", "<b>Quantity</b>", "<b>Amount</b>"],
      ["GoRails Subscription", "$19.00", "1", "$19.00"],
      [nil, nil, "Subtotal", "$19.00"],
      [nil, nil, "Tax Rate", "0%"],
      [nil, nil, "Amount Due", "$19.00"],
    ],
  ).render_file "examples/invoice.pdf"
end

task :statement do
  require "./lib/receipts"

  Receipts::Statement.new(
    id: "123",
    issue_date: Date.today,
    start_date: Date.today - 30,
    end_date: Date.today,
    bill_to: [
      "GoRails, LLC",
      "123 Fake Street",
      "New York City, NY 10012",
      nil,
      "mail@example.com",
    ],
    company: {
      name: "GoRails, LLC",
      address: "123 Fake Street\nNew York City, NY 10012",
      email: "support@example.com",
      logo: File.expand_path("./examples/gorails.png")
    },
    line_items: [
      ["<b>Item</b>", "<b>Unit Cost</b>", "<b>Quantity</b>", "<b>Amount</b>"],
      ["GoRails Subscription", "$19.00", "1", "$19.00"],
      [nil, nil, "Subtotal", "$19.00"],
      [nil, nil, "Tax Rate", "0%"],
      [nil, nil, "Total", "$19.00"],
    ],
  ).render_file "examples/statement.pdf"
end
