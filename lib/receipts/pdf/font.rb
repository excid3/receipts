module Receipts
  module PDF
    # A TrueType font used in a document. Tracks which glyphs are used so only
    # those are embedded when the document is rendered.
    class Font
      # Skew applied to fake an italic style when a font family has no italic font
      OBLIQUE_SKEW = Math.tan(12 * Math::PI / 180)

      attr_reader :ttf

      def initialize(path)
        @ttf = TrueType.load(path)
        @used = {}
        @widths = {}
      end

      def width_of(text, size, character_spacing: 0)
        units = text.each_char.sum { |char| @widths[char] ||= @ttf.advance(@ttf.glyph_id(char.ord)) }
        scale(units, size) + character_spacing * text.length
      end

      def ascender(size)
        scale(@ttf.ascender, size)
      end

      # Distance below the baseline, as a positive number
      def descender(size)
        -scale(@ttf.descender, size)
      end

      def line_gap(size)
        scale(@ttf.line_gap, size)
      end

      def underline_position(size)
        scale(@ttf.underline_position, size)
      end

      def underline_thickness(size)
        scale(@ttf.underline_thickness, size)
      end

      def strikeout_position(size)
        scale(@ttf.strikeout_position, size)
      end

      def strikeout_size(size)
        scale(@ttf.strikeout_size, size)
      end

      def bold?
        @ttf.weight >= 600
      end

      # Encodes text as 2-byte original glyph IDs (Identity-H encoding)
      def encode(text)
        text.each_char.map do |char|
          gid = @ttf.glyph_id(char.ord)
          @used[gid] ||= char
          gid
        end.pack("n*")
      end

      def build(writer)
        gids = @used.keys.sort
        subset, mapping = @ttf.subset(gids)
        name = :"#{subset_tag(gids)}+#{@ttf.postscript_name}"

        font_file = writer.add(Stream.new(subset, {Length1: subset.bytesize}))
        descriptor = writer.add(
          Type: :FontDescriptor,
          FontName: name,
          Flags: flags,
          FontBBox: @ttf.bbox.map { |v| to_glyph_space(v) },
          ItalicAngle: @ttf.italic_angle,
          Ascent: to_glyph_space(@ttf.ascender),
          Descent: to_glyph_space(@ttf.descender),
          CapHeight: to_glyph_space(@ttf.cap_height),
          XHeight: to_glyph_space(@ttf.x_height),
          StemV: bold? ? 120 : 80,
          FontFile2: font_file
        )
        cid_font = writer.add(
          Type: :Font,
          Subtype: :CIDFontType2,
          BaseFont: name,
          CIDSystemInfo: {Registry: "Adobe", Ordering: "Identity", Supplement: 0},
          FontDescriptor: descriptor,
          DW: to_glyph_space(@ttf.advance(0)),
          W: glyph_widths(gids),
          CIDToGIDMap: writer.add(Stream.new(cid_to_gid_map(gids, mapping)))
        )
        writer.add(
          Type: :Font,
          Subtype: :Type0,
          BaseFont: name,
          Encoding: :"Identity-H",
          DescendantFonts: [cid_font],
          ToUnicode: writer.add(Stream.new(to_unicode_cmap))
        )
      end

      private

      def scale(units, size)
        units * size / @ttf.units_per_em.to_f
      end

      def to_glyph_space(units)
        (units * 1000.0 / @ttf.units_per_em).round
      end

      def flags
        flags = 32 # Nonsymbolic
        flags |= 1 if @ttf.fixed_pitch?
        flags |= 64 unless @ttf.italic_angle.zero?
        flags
      end

      # Subset fonts are named with a tag of 6 uppercase letters, like ABCDEF+Inter-Regular
      def subset_tag(gids)
        Digest::MD5.digest(gids.pack("n*") + @ttf.postscript_name).bytes.first(6).map { |b| (65 + b % 26).chr }.join
      end

      # Text is encoded with the original glyph IDs as CIDs. This maps them to the renumbered subset glyphs.
      def cid_to_gid_map(gids, mapping)
        map = Array.new((gids.max || 0) + 1, 0)
        gids.each { |gid| map[gid] = mapping.fetch(gid) }
        map.pack("n*")
      end

      # Widths array grouping consecutive glyph IDs: [first [w1 w2 ...] first [w1 ...]]
      def glyph_widths(gids)
        gids.slice_when { |a, b| b != a + 1 }.flat_map do |run|
          [run.first, run.map { |gid| to_glyph_space(@ttf.advance(gid)) }]
        end
      end

      # Maps glyph IDs back to Unicode so text can be copied and searched
      def to_unicode_cmap
        mappings = @used.sort.map do |gid, char|
          format("<%04X> <%s>", gid, char.encode(Encoding::UTF_16BE).unpack1("H*").upcase)
        end

        blocks = mappings.each_slice(100).map do |slice|
          "#{slice.size} beginbfchar\n#{slice.join("\n")}\nendbfchar"
        end

        <<~CMAP
          /CIDInit /ProcSet findresource begin
          12 dict begin
          begincmap
          /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
          /CMapName /Adobe-Identity-UCS def
          /CMapType 2 def
          1 begincodespacerange
          <0000> <FFFF>
          endcodespacerange
          #{blocks.join("\n")}
          endcmap
          CMapName currentdict /CMap defineresource pop
          end
          end
        CMAP
      end
    end
  end
end
