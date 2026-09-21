module Receipts
  module PDF
    # Wraps styled text into lines that fit a given width.
    #
    # Input is an Array of [text, Style] chunks. Lines break at spaces, after
    # hyphens, and at newlines. Words wider than the line are broken anywhere.
    module TextLayout
      Style = Struct.new(:font, :size, :color, :link, :underline, :strikethrough, :rise,
        :character_spacing, :oblique, :fake_bold, keyword_init: true)
      Run = Struct.new(:text, :style, :width)
      Line = Struct.new(:runs, :width, :ascender, :descender, :line_gap)

      EPSILON = 0.0001

      module_function

      def wrap(chunks, max_width, default_style)
        lines = []

        paragraphs(chunks, default_style).each do |paragraph_style, paragraph|
          line = []
          line_width = 0
          pending = []
          pending_width = 0

          items(paragraph).each do |type, pieces|
            width = pieces.sum { |text, style| measure(text, style) }

            if type == :space
              next if line.empty?
              pending.concat(pieces)
              pending_width += width
              next
            end

            if line.any? && line_width + pending_width + width > max_width + EPSILON
              lines << build_line(line, paragraph_style)
              line = []
              line_width = 0
            else
              line.concat(pending)
              line_width += pending_width
            end
            pending = []
            pending_width = 0

            if line.empty? && width > max_width + EPSILON
              pieces, width = break_word(pieces, max_width, paragraph_style, lines)
            end

            line.concat(pieces)
            line_width += width
          end

          lines << build_line(line, paragraph_style)
        end

        lines
      end

      # Width of the text without wrapping
      def natural_width(chunks, default_style)
        paragraphs(chunks, default_style).map do |_, paragraph|
          paragraph.sum { |text, style| measure(text, style) }
        end.max || 0
      end

      # Width of the widest word, the narrowest the text can wrap without breaking words
      def minimum_width(chunks, default_style)
        paragraphs(chunks, default_style).flat_map do |_, paragraph|
          items(paragraph).map { |type, pieces| (type == :word) ? pieces.sum { |text, style| measure(text, style) } : 0 }
        end.max || 0
      end

      def height_of(lines, leading = 0)
        return 0 if lines.empty?
        lines.sum { |line| line.ascender + line.descender } + lines[0...-1].sum { |line| line.line_gap + leading }
      end

      def measure(text, style)
        style.font.width_of(text, style.size, character_spacing: style.character_spacing)
      end

      # Splits chunks at newlines. Empty paragraphs keep the style of the text around them for their height.
      def paragraphs(chunks, default_style)
        paragraphs = [[default_style, []]]
        chunks.each do |text, style|
          paragraphs.last[0] = style if paragraphs.last[1].empty?
          text.split("\n", -1).each_with_index do |part, index|
            paragraphs << [style, []] if index > 0
            paragraphs.last[1] << [part, style] unless part.empty?
          end
        end
        paragraphs
      end

      # Groups text into [:word, pieces] and [:space, pieces] items. A word can span
      # several chunks with different styles, like "<b>Total</b>:".
      def items(chunks)
        items = []
        word = nil

        chunks.each do |text, style|
          text.scan(/[ \t]+|[^ \t]+/) do |token|
            if token.start_with?(" ", "\t")
              items << [:space, [[token.tr("\t", " "), style]]]
              word = nil
            else
              token.scan(/[^-]*-+|[^-]+/) do |piece|
                unless word
                  word = []
                  items << [:word, word]
                end
                word << [piece, style]
                word = nil if piece.end_with?("-")
              end
            end
          end
        end

        items
      end

      # Breaks a word too wide for a line into full lines, returning the remainder
      def break_word(pieces, max_width, paragraph_style, lines)
        current = []
        current_width = 0

        pieces.each do |text, style|
          text.each_char do |char|
            width = measure(char, style)
            if current.any? && current_width + width > max_width + EPSILON
              lines << build_line(current, paragraph_style)
              current = []
              current_width = 0
            end
            current << [char, style]
            current_width += width
          end
        end

        [current, current_width]
      end

      def build_line(pieces, fallback_style)
        runs = []
        pieces.each do |text, style|
          if runs.any? && runs.last.style.equal?(style)
            runs.last.text += text
          else
            runs << Run.new(text.dup, style, 0)
          end
        end
        runs.each { |run| run.width = measure(run.text, run.style) }

        styles = runs.empty? ? [fallback_style] : runs.map(&:style)
        Line.new(
          runs,
          runs.sum(&:width),
          styles.map { |s| s.font.ascender(s.size) + s.rise }.max,
          styles.map { |s| s.font.descender(s.size) - s.rise }.max,
          styles.map { |s| s.font.line_gap(s.size) }.max
        )
      end
    end
  end
end
