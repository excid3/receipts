# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

task default: :test

task :console do
  exec "irb -r receipts -I ./lib"
end

task :examples do
  [:receipt, :invoice, :statement].each { |t| Rake::Task[t].invoke }
  puts "Use `open examples` to view example PDFs."
end

task :receipt do
  require "./lib/receipts"

  r = Receipts::Receipt.new(
    recipient: [
      "<b>Bill To</b>",
      "Customer",
      "Address",
      "City, State Zipcode",
      "customer@example.org"
    ],
    company: {
      name: "Example, LLC",
      address: "123 Fake Street\nNew York City, NY 10012",
      phone: "(555) 867-5309",
      email: "support@example.com",
      iban: "123456789",
      logo: File.expand_path("./examples/images/logo.png"),
      display: [:address, :phone, :email, nil, :iban]
    },
    details: [
      ["Receipt Number", "123"],
      ["Date paid", Date.today.strftime("%B %d, %Y")],
      ["Payment method", "ACH super long super long super long super long super long"]
    ],
    line_items: [
      ["<b>Item</b>", "<b>Unit Cost</b>", "<b>Quantity</b>", "<b>Amount</b>"],
      ["Subscription", "$19.00", "1", "$19.00"],
      [nil, nil, "Subtotal", "$19.00"],
      [nil, nil, "Tax", "$1.12"],
      [nil, nil, "Total", "$20.12"],
      [nil, nil, "<b>Amount paid</b>", "$20.12"],
      [nil, nil, "Refunded on #{Date.today.strftime("%B %d, %Y")}", "$5.00"]
    ]
  )
  r.render_file "examples/receipt.pdf"
end

task :invoice do
  require "./lib/receipts"

  Receipts::Invoice.new(
    details: [
      ["Invoice Number", "123"],
      ["Issue Date", Date.today.strftime("%B %d, %Y")],
      ["Due Date", Date.today.strftime("%B %d, %Y")],
      ["Status", "<b><color rgb='#5eba7d'>PAID</color></b>"]
    ],
    recipient: [
      "<b>Bill To</b>",
      "Customer",
      "Address",
      "City, State Zipcode",
      "customer@example.org"
    ],
    company: {
      name: "Example, LLC",
      address: "123 Fake Street\nNew York City, NY 10012",
      phone: "(555) 867-5309",
      email: "support@example.com",
      # logo: Rails.root.join("app/assets/images/logo.png")
      # logo: File.open("./examples/images/logo.png")
      logo: File.expand_path("./examples/images/logo.png")
    },
    line_items: [
      ["<b>Item</b>", "<b>Unit Cost</b>", "<b>Quantity</b>", "<b>Amount</b>"],
      ["Subscription", "$19.00", "1", "$19.00"],
      [nil, nil, "Subtotal", "$19.00"],
      [nil, nil, "Tax Rate", "0%"],
      [nil, nil, "Amount Due", "$19.00"]
    ]
  ).render_file "examples/invoice.pdf"
end

task :statement do
  require "./lib/receipts"

  Receipts::Statement.new(
    details: [
      ["Statement Number", "123"],
      ["Issue Date", Date.today.strftime("%B %d, %Y")],
      ["Period", "#{(Date.today - 30).strftime("%B %d, %Y")} - #{Date.today.strftime("%B %d, %Y")}"]
    ],
    recipient: [
      "<b>Bill To</b>",
      "Customer",
      "Address",
      "City, State Zipcode",
      "customer@example.org"
    ],
    company: {
      name: "Example, LLC",
      address: "123 Fake Street\nNew York City, NY 10012",
      email: "support@example.com",
      phone: "(555) 867-5309",
      logo: File.expand_path("./examples/images/logo.png")
    },
    line_items: [
      ["<b>Item</b>", "<b>Unit Cost</b>", "<b>Quantity</b>", "<b>Amount</b>"],
      ["Subscription", "$19.00", "1", "$19.00"],
      [nil, nil, "Subtotal", "$19.00"],
      [nil, nil, "Tax Rate", "0%"],
      [nil, nil, "Total", "$19.00"]
    ]
  ).render_file "examples/statement.pdf"
end
