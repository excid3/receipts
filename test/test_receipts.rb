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

  def test_invoice_with_additional_company_data
    assert_instance_of Receipts::Invoice, Receipts::Invoice.new(
      company: {
        name: "Company",
        address: "123 Street",
        email: "company@example.org",
        company_code: "000123",
        iban: "LT241997677264666618"
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
end
