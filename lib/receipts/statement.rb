module Receipts
  class Statement < Base
    attr_reader :attributes, :id, :company, :custom_font, :line_items, :logo, :message, :product, :subheading, :bill_to, :issue_date, :start_date, :end_date

    def initialize(attributes)
      @attributes = attributes
      @id = attributes.fetch(:id)
      @company = attributes.fetch(:company)
      @line_items = attributes.fetch(:line_items)
      @custom_font = attributes.fetch(:font, {})
      @message = attributes.fetch(:message) { default_message }
      @subheading = attributes.fetch(:subheading) { default_subheading }
      @bill_to = Array(attributes.fetch(:bill_to)).join("\n")
      @issue_date = attributes.fetch(:issue_date)
      @start_date = attributes.fetch(:start_date)
      @end_date = attributes.fetch(:end_date)

      super(page_size: "LETTER")

      setup_fonts if custom_font.any?
      generate
    end

    private

    def default_message
      "For questions, contact us anytime at <color rgb='326d92'><link href='mailto:#{company.fetch(:email)}?subject=Charge ##{id}'><b>#{company.fetch(:email)}</b></link></color>."
    end

    def default_subheading
      "STATEMENT #%{id}"
    end

    def generate
      header
      description
      statement_details
      charge_details
      footer
    end

    def header(height: 24)
      logo = company[:logo]
      return if logo.nil?
      image load_image(logo), height: height
    end

    def description
      move_down 8
      text label(subheading % {id: id}), inline_format: true, leading: 4
    end

    def statement_details
      move_down 10
      font_size 9

      line_items = [
        [{content: "#{label("BILL TO")}\n#{bill_to}", rowspan: 3, padding: [0, 12, 0, 0]}, "#{label("INVOICE DATE")}\n#{issue_date}"],
        ["#{label("STATEMENT DATE")}\n#{issue_date}"],
        ["#{label("STATEMENT PERIOD")}\n#{start_date} - #{end_date}"]
      ]
      table(line_items, width: bounds.width, cell_style: {inline_format: true, overflow: :shrink_to_fit}) do
        cells.borders = []
      end
    end

    def charge_details
      move_down 30

      borders = line_items.length - 2

      table(line_items, width: bounds.width, cell_style: {border_color: "cccccc", inline_format: true}) do
        cells.padding = 10
        cells.borders = []
        row(0..borders).borders = [:bottom]
      end
    end

    def footer
      move_down 30
      text message, inline_format: true, leading: 4

      move_down 30
      text company.fetch(:name), inline_format: true
      text "<color rgb='888888'>#{company.fetch(:address)}</color>", inline_format: true
    end
  end
end
