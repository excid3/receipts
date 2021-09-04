require "receipts/version"
require "open-uri"
require "prawn"
require "prawn/table"

module Receipts
  autoload :Invoice, "receipts/invoice"
  autoload :Receipt, "receipts/receipt"
  autoload :Statement, "receipts/statement"

  class Base < Prawn::Document
    def setup_fonts
      font_families.update "Primary" => custom_font
      font "Primary"
    end

    def load_image(logo)
      if logo.is_a? String
        logo.start_with?("http") ? URI.parse(logo).open : File.open(logo)
      else
        logo
      end
    end

    def label(text)
      "<font size='8'><color rgb='a6a6a6'>#{text}</color></font>"
    end
  end
end
