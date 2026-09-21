module Receipts
  module PDF
    # Parses HTML-like inline formatting into styled text fragments:
    #   <b> <strong> <i> <em> <u> <strikethrough> <sub> <sup> <br>
    #   <font name="..." size="..." character_spacing="...">
    #   <color rgb="#ff0000"> or <color c="0" m="100" y="100" k="0">
    #   <link href="..."> or <a href="...">
    #
    # Each fragment is a Hash with :text and any of :styles, :color, :link,
    # :font, :size and :character_spacing.
    module InlineFormat
      TAG = %r{<(/?)(b|strong|i|em|u|strikethrough|sub|sup|font|color|link|a|br)(\s[^>]*?)?\s*/?>}i
      ATTRIBUTE = /(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)')/
      ENTITIES = {"&lt;" => "<", "&gt;" => ">", "&amp;" => "&"}.freeze
      STYLES = {
        "b" => :bold, "strong" => :bold, "i" => :italic, "em" => :italic, "u" => :underline,
        "strikethrough" => :strikethrough, "sub" => :subscript, "sup" => :superscript
      }.freeze

      module_function

      def parse(string)
        fragments = []
        stack = [[nil, {}]]
        pos = 0

        while (match = TAG.match(string, pos))
          add(fragments, string[pos...match.begin(0)], stack.last.last)
          name = match[2].downcase

          if name == "br"
            add(fragments, "\n", stack.last.last)
          elsif match[1] == "/"
            index = stack.rindex { |tag, _| tag == name }
            stack = stack.first(index) if index
          else
            stack.push([name, apply(stack.last.last, name, attributes(match[3].to_s))])
          end

          pos = match.end(0)
        end

        add(fragments, string[pos..], stack.last.last)
        fragments
      end

      def add(fragments, text, style)
        return if text.empty?
        fragments << style.merge(text: text.gsub(/&(?:lt|gt|amp);/, ENTITIES))
      end

      def attributes(string)
        string.scan(ATTRIBUTE).map { |key, double, single| [key.downcase, double || single] }.to_h
      end

      def apply(style, name, attributes)
        style = style.dup

        if STYLES.key?(name)
          style[:styles] = Array(style[:styles]) | [STYLES[name]]
        elsif name == "font"
          style[:font] = attributes["name"] if attributes["name"]
          style[:size] = attributes["size"].to_f if attributes["size"]
          style[:character_spacing] = attributes["character_spacing"].to_f if attributes["character_spacing"]
        elsif name == "color"
          if attributes["rgb"]
            style[:color] = attributes["rgb"].delete("#")
          elsif %w[c m y k].all? { |key| attributes.key?(key) }
            style[:color] = attributes.values_at("c", "m", "y", "k").map(&:to_f)
          end
        elsif attributes["href"]
          style[:link] = attributes["href"]
        end

        style
      end
    end
  end
end
