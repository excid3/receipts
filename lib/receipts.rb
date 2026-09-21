require "receipts/version"
require "open-uri"
require "receipts/pdf/geometry"
require "receipts/pdf/writer"
require "receipts/pdf/true_type"
require "receipts/pdf/font"
require "receipts/pdf/image"
require "receipts/pdf/inline_format"
require "receipts/pdf/text_layout"
require "receipts/pdf/table"
require "receipts/pdf/document"

module Receipts
  autoload :Base, "receipts/base"
  autoload :Invoice, "receipts/invoice"
  autoload :Receipt, "receipts/receipt"
  autoload :Statement, "receipts/statement"

  @@default_font = nil

  # Customize the default font hash
  # default_font = {
  #   bold: "path/to/font",
  #   normal: "path/to/font",
  # }
  def self.default_font=(path)
    @@default_font = path
  end

  def self.default_font
    @@default_font
  end
end
