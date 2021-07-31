require "open-uri"
require "receipts/version"

module Receipts
  autoload :Invoice, "receipts/invoice"
  autoload :Receipt, "receipts/receipt"
  autoload :Statement, "receipts/statement"
end
