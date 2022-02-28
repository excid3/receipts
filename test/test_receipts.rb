# frozen_string_literal: true

require "test_helper"

class TestReceipts < Minitest::Test
  def test_without_arguments
    assert_instance_of Receipts::Receipt, Receipts::Receipt.new
  end

  def test_customization
    assert Receipts::Receipt.new.respond_to?(:text)
  end

  def test_renderable
    assert Receipts::Receipt.new.respond_to?(:render_file)
  end

  def test_receipt_with_arguments
    assert_instance_of Receipts::Receipt, Receipts::Receipt.new(
      company: {
        name: "Company",
        address: "123 Street",
        email: "company@example.org"
      },
      recipient: [],
      details: [
        ["Receipt", "123"]
      ],
      line_items: [
        ["Product", "$10"]
      ]
    )
  end

  def test_invoice_with_arguments
    assert_instance_of Receipts::Invoice, Receipts::Invoice.new(
      company: {
        name: "Company",
        address: "123 Street",
        email: "company@example.org"
      },
      recipient: [],
      details: [
        ["Receipt", "123"]
      ],
      line_items: [
        ["Product", "$10"]
      ]
    )
  end

  def test_statement_with_arguments
    assert_instance_of Receipts::Statement, Receipts::Statement.new(
      company: {
        name: "Company",
        address: "123 Street",
        email: "company@example.org"
      },
      recipient: [],
      details: [
        ["Receipt", "123"]
      ],
      line_items: [
        ["Product", "$10"]
      ]
    )
  end

  def test_logo_arguments
    template = {
      company: {
        name: "Company",
        address: "123 Street",
        email: "company@example.org"
      },
      recipient: [],
      details: [
        ["Receipt", "123"]
      ],
      line_items: [
        ["Product", "$10"]
      ]
    }

    # Writing receipts to files, to be visually inspected
    { "./examples/images/logo.png" => "logo-from-local-file",
      Pathname.new("examples/images/logo.png") => "logo-from-local-file",
      false => "logo-completely-disabled",
      nil => "logo-nil-outputs-company-name",
      "This is my logo" => "logo-from-string",
      "https://plchldr.co/i/300x100?&bg=aaa4a2&fc=000000&text=My%20Logo" => "logo-from-url"
    }.each_pair do |logo, output|
      template[:company][:logo] = logo
      obj = Receipts::Receipt.new(template)
      assert_instance_of Receipts::Receipt, obj
      obj.render_file("/tmp/receipts-test--#{output}.pdf")
    end
  end
end
