module Receipts
  module PDF
    # A minimal PDF document with a Prawn-like API for flowing text, images and tables.
    #
    # Coordinates follow PDF conventions: the origin is the bottom left of the page
    # and units are points (1/72 inch).
    class Document
      PAGE_SIZES = {
        "A3" => [841.89, 1190.55],
        "A4" => [595.28, 841.89],
        "A5" => [419.53, 595.28],
        "LEGAL" => [612.0, 1008.0],
        "LETTER" => [612.0, 792.0],
        "TABLOID" => [792.0, 1224.0]
      }.freeze

      FONTS_PATH = File.expand_path("../fonts", __dir__)
      DEFAULT_FONT_FAMILY = "Inter"
      DEFAULT_FONT = {
        normal: File.join(FONTS_PATH, "Inter-Regular.ttf"),
        bold: File.join(FONTS_PATH, "Inter-Bold.ttf")
      }.freeze

      # The area inside the page margins. Like Prawn, `left`, `right`, `top` and
      # `bottom` are relative to the box, while the absolute_* values are page coordinates.
      Bounds = Struct.new(:absolute_left, :absolute_bottom, :width, :height) do
        def left
          0
        end

        def bottom
          0
        end

        def right
          width
        end

        def top
          height
        end

        def absolute_right
          absolute_left + width
        end

        def absolute_top
          absolute_bottom + height
        end
      end

      Page = Struct.new(:content, :annotations)

      attr_reader :bounds, :font_families, :page_width, :page_height
      attr_accessor :y, :fill_color, :stroke_color, :line_width

      def initialize(page_size: "LETTER", page_layout: :portrait, margin: 36, info: {})
        width, height = page_size.is_a?(Array) ? page_size : PAGE_SIZES.fetch(page_size.to_s.upcase) {
          raise ArgumentError, "unknown page size #{page_size.inspect}, use one of #{PAGE_SIZES.keys.join(", ")} or [width, height]"
        }
        width, height = height, width if page_layout == :landscape
        @page_width = width
        @page_height = height

        top, right, bottom, left = Geometry.expand_box(margin)
        @bounds = Bounds.new(left, bottom, width - left - right, height - top - bottom)

        @info = info
        @font_families = {DEFAULT_FONT_FAMILY => DEFAULT_FONT.dup}
        @font_family = DEFAULT_FONT_FAMILY
        @font_size = 12
        @fill_color = "000000"
        @stroke_color = "000000"
        @line_width = 1
        @fonts = {}
        @font_resources = {}.compare_by_identity
        @images = {}.compare_by_identity
        @pages = []

        start_new_page
      end

      def start_new_page
        @pages << Page.new(String.new(encoding: Encoding::BINARY), [])
        @y = @bounds.absolute_top
      end

      # Starts a new page if there isn't room for height, unless already at the top of one.
      # Returns true when a new page was started.
      def start_new_page_if_needed(height)
        return false unless @y - height < @bounds.absolute_bottom && @y < @bounds.absolute_top
        start_new_page
        true
      end

      def page_count
        @pages.size
      end

      # Distance from the current position to the bottom margin
      def cursor
        @y - @bounds.absolute_bottom
      end

      def move_down(amount)
        @y -= amount
      end

      def move_up(amount)
        @y += amount
      end

      def move_cursor_to(position)
        @y = @bounds.absolute_bottom + position
      end

      # Sets the font family (or a path to a .ttf file), optionally just for the given block
      def font(name = nil, size: nil)
        return @font_family if name.nil? && size.nil?

        previous = [@font_family, @font_size]
        @font_family = name.to_s if name
        @font_size = size if size
        return unless block_given?

        begin
          yield
        ensure
          @font_family, @font_size = previous
        end
      end

      def font_size(size = nil, &block)
        return @font_size if size.nil?
        return @font_size = size unless block
        font(nil, size: size, &block)
      end

      def width_of(string, options = {})
        TextLayout.natural_width(text_chunks(string, options), text_style(options))
      end

      def height_of(string, options = {})
        TextLayout.height_of(text_lines(string, options, @bounds.width), options.fetch(:leading, 0))
      end

      # Writes flowing text at the cursor, wrapping lines and starting new pages as needed.
      #
      # Options: :size, :style (:bold, :italic, :bold_italic), :align (:left, :center, :right),
      # :color (hex RGB), :font, :character_spacing, :leading, :inline_format
      def text(string, options = {})
        lines = text_lines(string, options, @bounds.width)
        leading = options.fetch(:leading, 0)

        lines.each_with_index do |line, index|
          start_new_page_if_needed(line.height)
          draw_text_line(line, @bounds.absolute_left, @y - line.ascender, @bounds.width, options.fetch(:align, :left))
          @y -= line.height
          @y -= line.line_gap + leading if index < lines.size - 1
        end
        nil
      end

      # Draws an image at the cursor. Given only a width or height, the other is
      # scaled proportionally. Images wider than the bounds are scaled down to fit.
      #
      # Position is :left, :center, :right or an x offset from the left bound.
      def image(source, width: nil, height: nil, position: :left)
        image = Image.load(source)
        width ||= height ? image.width * height.to_f / image.height : [image.width, @bounds.width].min.to_f
        height ||= image.height * width.to_f / image.width
        x = @bounds.absolute_left + Geometry.align_offset(position, @bounds.width, width)

        start_new_page_if_needed(height)

        name = @images[image] ||= :"I#{@images.size + 1}"
        add_content "q #{n(width)} 0 0 #{n(height)} #{n(x)} #{n(@y - height)} cm /#{name} Do Q"
        @y -= height
        nil
      end

      # Draws a table at the cursor. See Receipts::PDF::Table for options.
      def table(data, options = {}, &block)
        Table.new(self, data, options, &block).draw
      end

      def stroke_horizontal_rule
        stroke_line(@bounds.absolute_left, @y, @bounds.absolute_right, @y)
      end

      def stroke_line(x1, y1, x2, y2, color: @stroke_color, width: @line_width)
        add_content "q #{color_operator(color, stroke: true)} #{n(width)} w #{n(x1)} #{n(y1)} m #{n(x2)} #{n(y2)} l S Q"
      end

      def fill_rectangle(x, y, width, height, color: @fill_color)
        add_content "q #{color_operator(color)} #{n(x)} #{n(y)} #{n(width)} #{n(height)} re f Q"
      end

      def render
        writer = Writer.new

        fonts = @font_resources.map { |font, name| [name, font.build(writer)] }.to_h
        images = @images.map { |image, name| [name, image.build(writer)] }.to_h
        resources = {}
        resources[:Font] = fonts if fonts.any?
        resources[:XObject] = images if images.any?
        resources = writer.add(resources)

        pages = writer.reserve
        kids = @pages.map do |page|
          dictionary = {
            Type: :Page,
            Parent: pages,
            MediaBox: [0, 0, @page_width, @page_height],
            Resources: resources,
            Contents: writer.add(Stream.new(page.content))
          }
          dictionary[:Annots] = page.annotations.map { |annotation| writer.add(annotation) } if page.annotations.any?
          writer.add(dictionary)
        end
        writer.set(pages, Type: :Pages, Kids: kids, Count: kids.size)

        info = {Producer: "Receipts"}.merge(@info).transform_values { |value| Serializer.text_string(value) }
        writer.render(root: writer.add(Type: :Catalog, Pages: pages), info: writer.add(info))
      end

      def render_file(path)
        File.binwrite(path, render)
      end

      # [natural width, widest word] of text, used to size table columns
      def measure_text(string, options = {})
        chunks = text_chunks(string, options)
        style = text_style(options)
        [TextLayout.natural_width(chunks, style), TextLayout.minimum_width(chunks, style)]
      end

      # Lays out text into lines for the given width without drawing it
      def text_lines(string, options, width)
        TextLayout.wrap(text_chunks(string, options), width, text_style(options))
      end

      # Draws lines of text top-down from top, returning the height used
      def draw_text_lines(lines, x, top, width, align: :left, leading: 0)
        y = top
        lines.each_with_index do |line, index|
          draw_text_line(line, x, y - line.ascender, width, align)
          y -= line.height
          y -= line.line_gap + leading if index < lines.size - 1
        end
        top - y
      end

      private

      def add_content(operators)
        @pages.last.content << operators << "\n"
      end

      def n(value)
        Serializer.number(value)
      end

      def text_style(options, fragment = {})
        styles = style_list(options[:style]) | Array(fragment[:styles])
        size = fragment[:size] || options[:size] || @font_size
        rise = 0

        if styles.include?(:superscript)
          rise = size * 0.33
          size *= 0.583
        elsif styles.include?(:subscript)
          rise = -size * 0.2
          size *= 0.583
        end

        font, fake_bold, oblique = resolve_font(fragment[:font] || options[:font] || @font_family, styles)

        TextLayout::Style.new(
          font: font,
          size: size,
          color: fragment[:color] || options[:color] || @fill_color,
          link: fragment[:link],
          underline: styles.include?(:underline),
          strikethrough: styles.include?(:strikethrough),
          rise: rise,
          character_spacing: fragment[:character_spacing] || options[:character_spacing] || 0,
          oblique: oblique,
          fake_bold: fake_bold
        )
      end

      def text_chunks(string, options)
        string = string.to_s
        string = string.dup.force_encoding(Encoding::UTF_8) if string.encoding == Encoding::BINARY
        string = string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).scrub.delete("\r")

        fragments = options[:inline_format] ? InlineFormat.parse(string) : [{text: string}]
        fragments.map { |fragment| [fragment[:text], text_style(options, fragment)] }
      end

      def style_list(style)
        case style
        when nil, :normal then []
        when :bold_italic then [:bold, :italic]
        when Array then style
        else [style.to_sym]
        end
      end

      # Picks the font for a style, faking bold or italic when the family doesn't include it.
      # Returns [font, fake_bold, oblique]
      def resolve_font(name, styles)
        name = name.to_s
        family = @font_families[name] || (name.end_with?(".ttf") && File.exist?(name) && {normal: name})
        raise ArgumentError, "unknown font #{name.inspect}, register it with font_families.update(#{name.inspect} => {normal: \"path/to/font.ttf\"})" unless family

        family = family.transform_keys(&:to_sym)
        bold = styles.include?(:bold)
        italic = styles.include?(:italic)
        key = [(:bold_italic if bold && italic), (:bold if bold), (:italic if italic), :normal].compact.find { |style| family[style] }
        raise ArgumentError, "font family #{name.inspect} needs a :normal font" unless key

        path = File.expand_path(family[key].to_s)
        font = @fonts[path] ||= Font.new(path).tap { |f| @font_resources[f] = :"F#{@font_resources.size + 1}" }
        [font, bold && !key.to_s.include?("bold"), italic && !key.to_s.include?("italic")]
      end

      def draw_text_line(line, x, baseline, width, align)
        x += Geometry.align_offset(align, width, line.width)

        line.runs.each do |run|
          draw_run(run, x, baseline)
          x += run.width
        end
      end

      def draw_run(run, x, baseline)
        style = run.style
        y = baseline + style.rise

        ops = ["q BT", "/#{@font_resources.fetch(style.font)} #{n(style.size)} Tf", color_operator(style.color)]
        ops << "#{n(style.character_spacing)} Tc" unless style.character_spacing.zero?
        ops << "2 Tr #{n(style.size * 0.03)} w #{color_operator(style.color, stroke: true)}" if style.fake_bold
        ops << "1 0 #{style.oblique ? n(Font::OBLIQUE_SKEW) : 0} 1 #{n(x)} #{n(y)} Tm"
        ops << "<#{style.font.encode(run.text).unpack1("H*")}> Tj ET Q"
        add_content ops.join(" ")

        font = style.font
        stroke_decoration(run, x, y, font.underline_position(style.size), font.underline_thickness(style.size)) if style.underline
        stroke_decoration(run, x, y, font.strikeout_position(style.size), font.strikeout_size(style.size)) if style.strikethrough

        if style.link
          @pages.last.annotations << {
            Type: :Annot,
            Subtype: :Link,
            Rect: [x, y - style.font.descender(style.size), x + run.width, y + style.font.ascender(style.size)],
            Border: [0, 0, 0],
            A: {Type: :Action, S: :URI, URI: style.link.to_s}
          }
        end
      end

      # Draws an underline or strikethrough line across a run at an offset from its baseline
      def stroke_decoration(run, x, baseline, offset, thickness)
        y = baseline + offset
        stroke_line(x, y, x + run.width, y, color: run.style.color, width: thickness)
      end

      # Hex RGB ("ff0000" or "#ff0000") or CMYK percentages ([0, 100, 100, 0])
      def color_operator(color, stroke: false)
        if color.is_a?(Array)
          "#{color.map { |c| n(c / 100.0) }.join(" ")} #{stroke ? "K" : "k"}"
        else
          hex = color.to_s.delete("#")
          hex = hex.chars.map { |c| c * 2 }.join if hex.size == 3
          raise ArgumentError, "invalid color #{color.inspect}" unless hex.match?(/\A\h{6}\z/)
          "#{[hex].pack("H*").bytes.map { |c| n(c / 255.0) }.join(" ")} #{stroke ? "RG" : "rg"}"
        end
      end
    end
  end
end
