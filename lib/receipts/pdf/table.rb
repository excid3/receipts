module Receipts
  module PDF
    # Simple tables with text cells, borders, padding and automatic column widths.
    #
    #   table(data, width: bounds.width, column_widths: [200, nil, 100], header: true,
    #     cell_style: {padding: 6, borders: [:bottom], border_color: "eeeeee", inline_format: true}) do
    #     row(0).font_style = :bold
    #     column(-1).align = :right
    #   end
    #
    # Cells may be strings, nil, or hashes with :content and cell options.
    class Table
      class Cell
        attr_accessor :content, :borders, :border_color, :border_width, :align, :font_style,
          :size, :text_color, :background_color, :inline_format, :font, :leading, :overflow
        attr_reader :padding

        def initialize(document, content, options = {})
          @document = document
          @content = content.to_s
          @padding = [5, 5, 5, 5]
          @borders = [:top, :right, :bottom, :left]
          @border_color = "000000"
          @border_width = 1
          @align = :left
          @inline_format = false
          @leading = 0
          options.each { |key, value| public_send(:"#{key}=", value) }
        end

        def padding=(value)
          @padding = @document.expand_box(value)
        end

        def horizontal_padding
          @padding[1] + @padding[3]
        end

        def vertical_padding
          @padding[0] + @padding[2]
        end

        def text_options
          {inline_format: @inline_format, style: @font_style, size: @size, color: @text_color, font: @font}.compact
        end

        def natural_width
          measure.first + horizontal_padding
        end

        def minimum_width
          measure.last + horizontal_padding
        end

        def lines(width)
          @document.text_lines(@content, text_options, [width - horizontal_padding, 0].max)
        end

        private

        def measure
          @measure ||= @document.measure_text(@content, text_options)
        end
      end

      # A selection of cells. Assigning an attribute sets it on every cell: `row(0).borders = [:bottom]`
      class Cells < Array
        def style(options)
          options.each { |key, value| public_send(:"#{key}=", value) }
          self
        end

        def method_missing(name, *args, &block)
          if name.to_s.end_with?("=") && Cell.method_defined?(name)
            each { |cell| cell.public_send(name, *args) }
          else
            super
          end
        end

        def respond_to_missing?(name, include_private = false)
          (name.to_s.end_with?("=") && Cell.method_defined?(name)) || super
        end
      end

      def initialize(document, data, options = {}, &block)
        @document = document
        @width = options[:width]
        @column_widths = options[:column_widths]
        @header = options[:header]
        @position = options.fetch(:position, :left)
        cell_style = options.fetch(:cell_style, {})

        columns = data.map { |row| Array(row).size }.max || 0
        @rows = data.map do |row|
          row = Array(row)
          Array.new(columns) do |index|
            value = row[index]
            if value.is_a?(Hash)
              Cell.new(document, value[:content], cell_style.merge(value.reject { |key, _| key == :content }))
            else
              Cell.new(document, value, cell_style)
            end
          end
        end

        return unless block
        (block.arity == 1) ? block.call(self) : instance_exec(&block)
      end

      def cells
        Cells.new(@rows.flatten)
      end

      def row(selector)
        Cells.new(select(@rows, selector).flatten)
      end
      alias_method :rows, :row

      def column(selector)
        Cells.new(@rows.flat_map { |row| select(row, selector) })
      end
      alias_method :columns, :column

      def column_widths
        @computed_column_widths ||= compute_column_widths
      end

      def draw
        widths = column_widths
        total = widths.sum
        bounds = @document.bounds
        offset = case @position
        when :center then (bounds.width - total) / 2.0
        when :right then bounds.width - total
        when Numeric then @position
        else 0
        end
        x = bounds.absolute_left + offset

        header_count = (@header == true) ? 1 : @header.to_i
        header_rows = @rows.first(header_count)

        @rows.each_with_index do |row, index|
          lines, height = layout_row(row, widths)

          if @document.y - height < bounds.absolute_bottom && @document.y < bounds.absolute_top
            @document.start_new_page
            if index >= header_rows.size
              header_rows.each { |header| draw_row(header, *layout_row(header, widths), widths, x) }
            end
          end

          draw_row(row, lines, height, widths, x)
        end

        nil
      end

      private

      def select(list, selector)
        selector.is_a?(Integer) ? [list[selector]].compact : Array(list[selector])
      end

      def layout_row(row, widths)
        lines = row.each_with_index.map { |cell, index| cell.lines(widths[index]) }
        height = row.each_with_index.map do |cell, index|
          TextLayout.height_of(lines[index], cell.leading) + cell.vertical_padding
        end.max || 0
        [lines, height]
      end

      def draw_row(row, lines, height, widths, x)
        top = @document.y

        row.each_with_index do |cell, index|
          width = widths[index]
          bottom = top - height

          @document.fill_rectangle(x, bottom, width, height, color: cell.background_color) if cell.background_color

          @document.draw_text_lines(lines[index], x + cell.padding[3], top - cell.padding[0],
            width - cell.horizontal_padding, align: cell.align, leading: cell.leading)

          Array(cell.borders).each do |border|
            case border
            when :top then @document.stroke_line(x, top, x + width, top, color: cell.border_color, width: cell.border_width)
            when :bottom then @document.stroke_line(x, bottom, x + width, bottom, color: cell.border_color, width: cell.border_width)
            when :left then @document.stroke_line(x, top, x, bottom, color: cell.border_color, width: cell.border_width)
            when :right then @document.stroke_line(x + width, top, x + width, bottom, color: cell.border_color, width: cell.border_width)
            end
          end

          x += width
        end

        @document.y = top - height
      end

      # Columns start at their natural (unwrapped) width. When the table is too wide,
      # narrow columns keep their width and wider columns shrink proportionally.
      # When a table width is given and there's space left over, it's split evenly between columns.
      def compute_column_widths
        count = @rows.first&.size || 0
        natural = Array.new(count) { |i| @rows.map { |row| row[i].natural_width }.max }
        minimum = Array.new(count) { |i| @rows.map { |row| row[i].minimum_width }.max }

        fixed = case @column_widths
        when Array then @column_widths.each_with_index.map { |width, i| [i, width] }.reject { |_, width| width.nil? }.to_h
        when Hash then @column_widths
        when Numeric then (0...count).map { |i| [i, @column_widths] }.to_h
        else {}
        end

        widths = natural.dup
        fixed.each { |i, width| widths[i] = width }
        flexible = (0...count).reject { |i| fixed.key?(i) }
        return widths if flexible.empty?

        target = @width || [widths.sum, @document.bounds.width].min
        available = target - fixed.values.sum
        flexible_natural = flexible.sum { |i| natural[i] }

        if flexible_natural > available
          budget = available
          columns = flexible.dup
          loop do
            share = budget / columns.size.to_f
            narrow = columns.select { |i| natural[i] <= share }
            break if narrow.empty?
            budget -= narrow.sum { |i| natural[i] }
            columns -= narrow
            break if columns.empty?
          end

          total = columns.sum { |i| natural[i] }
          columns.each { |i| widths[i] = total.zero? ? minimum[i] : [budget * natural[i] / total, minimum[i]].max }
        elsif @width && flexible_natural < available
          extra = (available - flexible_natural) / flexible.size.to_f
          flexible.each { |i| widths[i] += extra }
        end

        widths
      end
    end
  end
end
