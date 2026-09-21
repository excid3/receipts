require "set"

module Receipts
  module PDF
    class UnsupportedFontError < StandardError; end

    # Reads the tables of a TrueType (.ttf) font needed to measure text and
    # embed a subset of the font in a PDF.
    class TrueType
      REQUIRED_TABLES = %w[head hhea maxp hmtx cmap loca glyf].freeze

      # Hinting tables copied unchanged into subsets when present
      HINTING_TABLES = ["cvt ", "fpgm", "prep"].freeze

      CACHE = {}
      CACHE_MUTEX = Mutex.new
      CACHE_SIZE = 16

      attr_reader :units_per_em, :bbox, :ascender, :descender, :line_gap, :num_glyphs, :cmap,
        :italic_angle, :underline_position, :underline_thickness, :strikeout_position, :strikeout_size,
        :cap_height, :x_height, :weight, :postscript_name

      # Recently used fonts are cached by path since they're reused across documents,
      # and parsed again if the file changes
      def self.load(path)
        path = File.expand_path(path.to_s)
        mtime = File.mtime(path)

        CACHE_MUTEX.synchronize do
          cached_mtime, font = CACHE[path]
          unless cached_mtime == mtime
            font = new(File.binread(path))
            CACHE.delete(path)
            CACHE[path] = [mtime, font]
            CACHE.shift while CACHE.size > CACHE_SIZE
          end
          font
        end
      end

      def initialize(data)
        @data = data.b

        case @data.byteslice(0, 4)
        when "\x00\x01\x00\x00".b, "true"
          nil
        when "OTTO"
          raise UnsupportedFontError, "OpenType fonts with CFF outlines are not supported, use a TrueType (.ttf) font"
        when "ttcf"
          raise UnsupportedFontError, "TrueType collections (.ttc) are not supported, use a single TrueType (.ttf) font"
        else
          raise UnsupportedFontError, "not a TrueType font"
        end

        @tables = {}
        u16(4).times do |i|
          record = 12 + i * 16
          @tables[@data.byteslice(record, 4)] = [u32(record + 8), u32(record + 12)]
        end

        REQUIRED_TABLES.each do |tag|
          raise UnsupportedFontError, "font is missing the #{tag} table" unless @tables[tag]
        end

        parse_head
        parse_hhea
        parse_maxp
        parse_hmtx
        parse_loca
        parse_cmap
        parse_post
        parse_os2
        parse_name
      end

      def glyph_id(codepoint)
        @cmap.fetch(codepoint, 0)
      end

      def advance(gid)
        @advances[gid] || @advances.last
      end

      def fixed_pitch?
        @fixed_pitch
      end

      # Builds a font containing only the given glyphs (plus composite glyph parts),
      # renumbered compactly. Returns the font data and a Hash of original to new glyph IDs.
      def subset(gids)
        glyphs = glyph_closure(Set.new(gids) << 0).sort
        mapping = glyphs.each_with_index.to_h
        count = glyphs.size

        glyf = String.new(encoding: Encoding::BINARY)
        loca = []
        glyphs.each do |gid|
          loca << glyf.bytesize
          data = remap_components(glyph_data(gid), mapping)
          glyf << data << padding(data)
        end
        loca << glyf.bytesize

        head = table_data("head").dup
        head[8, 4] = [0].pack("N") # checkSumAdjustment, set below
        head[50, 2] = [1].pack("n") # indexToLocFormat: long offsets

        hhea = table_data("hhea").dup
        hhea[34, 2] = [count].pack("n") # numberOfHMetrics

        maxp = table_data("maxp").dup
        maxp[4, 2] = [count].pack("n") # numGlyphs

        hmtx = glyphs.flat_map { |gid| [advance(gid), left_side_bearing(gid)] }.pack("ns>" * count)

        tables = {"head" => head, "hhea" => hhea, "maxp" => maxp, "hmtx" => hmtx, "loca" => loca.pack("N*"), "glyf" => glyf}
        HINTING_TABLES.each { |tag| tables[tag] = table_data(tag) if @tables[tag] }

        if @tables["post"]
          # Version 3.0 post table: metrics only, no glyph names
          post = table_data("post").byteslice(0, 32).dup
          post[0, 4] = [0x00030000].pack("N")
          tables["post"] = post
        end

        [build_font(tables), mapping]
      end

      private

      def u16(offset)
        @data.byteslice(offset, 2).unpack1("n")
      end

      def i16(offset)
        @data.byteslice(offset, 2).unpack1("s>")
      end

      def u32(offset)
        @data.byteslice(offset, 4).unpack1("N")
      end

      def table_offset(tag)
        @tables[tag]&.first
      end

      def table_data(tag)
        offset, length = @tables.fetch(tag)
        @data.byteslice(offset, length)
      end

      def padding(data)
        "\0".b * (-data.bytesize % 4)
      end

      def parse_head
        t = table_offset("head")
        @units_per_em = u16(t + 18)
        @bbox = [i16(t + 36), i16(t + 38), i16(t + 40), i16(t + 42)]
        @index_to_loc_format = i16(t + 50)
      end

      def parse_hhea
        t = table_offset("hhea")
        @ascender = i16(t + 4)
        @descender = i16(t + 6)
        @line_gap = i16(t + 8)
        @number_of_hmetrics = u16(t + 34)
      end

      def parse_maxp
        @num_glyphs = u16(table_offset("maxp") + 4)
      end

      def parse_hmtx
        @hmtx_offset = table_offset("hmtx")
        @advances = @data.byteslice(@hmtx_offset, @number_of_hmetrics * 4).unpack("n*").each_slice(2).map(&:first)
      end

      def left_side_bearing(gid)
        if gid < @number_of_hmetrics
          i16(@hmtx_offset + gid * 4 + 2)
        else
          i16(@hmtx_offset + @number_of_hmetrics * 4 + (gid - @number_of_hmetrics) * 2)
        end
      end

      def parse_loca
        t = table_offset("loca")
        @loca = if @index_to_loc_format.zero?
          @data.byteslice(t, (@num_glyphs + 1) * 2).unpack("n*").map { |offset| offset * 2 }
        else
          @data.byteslice(t, (@num_glyphs + 1) * 4).unpack("N*")
        end
        @glyf_offset = table_offset("glyf")
      end

      def glyph_data(gid)
        return "".b if gid >= @num_glyphs
        @data.byteslice(@glyf_offset + @loca[gid], @loca[gid + 1] - @loca[gid])
      end

      def glyph_closure(gids)
        glyphs = Set.new
        queue = gids.to_a
        until queue.empty?
          gid = queue.pop
          next if gid >= @num_glyphs || !glyphs.add?(gid)
          each_component(glyph_data(gid)) { |_, component| queue << component }
        end
        glyphs
      end

      # Points composite glyphs at the renumbered IDs of their components
      def remap_components(data, mapping)
        copy = nil
        each_component(data) do |pos, component|
          copy ||= data.dup
          copy[pos, 2] = [mapping.fetch(component, 0)].pack("n")
        end
        copy || data
      end

      # Composite glyphs reference other glyphs. Yields the byte offset of each
      # component's glyph ID and the ID.
      def each_component(data)
        return if data.bytesize < 10 || data.unpack1("s>") >= 0

        pos = 10
        loop do
          flags, component = data.byteslice(pos, 4).unpack("nn")
          yield pos + 2, component
          pos += 4
          pos += (flags & 0x0001).zero? ? 2 : 4 # ARG_1_AND_2_ARE_WORDS
          if flags & 0x0008 != 0 # WE_HAVE_A_SCALE
            pos += 2
          elsif flags & 0x0040 != 0 # WE_HAVE_AN_X_AND_Y_SCALE
            pos += 4
          elsif flags & 0x0080 != 0 # WE_HAVE_A_TWO_BY_TWO
            pos += 8
          end
          break if (flags & 0x0020).zero? # MORE_COMPONENTS
        end
      end

      def parse_cmap
        t = table_offset("cmap")
        subtables = Array.new(u16(t + 2)) do |i|
          record = t + 4 + i * 8
          offset = t + u32(record + 4)
          [u16(record), u16(record + 2), offset, u16(offset)]
        end

        # Prefer full Unicode (format 12) over the Basic Multilingual Plane only (format 4)
        best = subtables.find { |platform, encoding, _, format| platform == 3 && encoding == 10 && format == 12 } ||
          subtables.find { |platform, _, _, format| platform == 0 && format == 12 } ||
          subtables.find { |platform, encoding, _, format| platform == 3 && encoding == 1 && format == 4 } ||
          subtables.find { |platform, _, _, format| platform == 0 && format == 4 }
        raise UnsupportedFontError, "font has no Unicode character map" unless best

        @cmap = (best[3] == 12) ? parse_cmap_format12(best[2]) : parse_cmap_format4(best[2])
      end

      def parse_cmap_format4(offset)
        map = {}
        seg_count = u16(offset + 6) / 2
        ends = offset + 14
        starts = ends + seg_count * 2 + 2
        deltas = starts + seg_count * 2
        range_offsets = deltas + seg_count * 2

        seg_count.times do |i|
          first = u16(starts + i * 2)
          last = u16(ends + i * 2)
          delta = u16(deltas + i * 2)
          range_offset_pos = range_offsets + i * 2
          range_offset = u16(range_offset_pos)

          (first..last).each do |codepoint|
            next if codepoint == 0xFFFF
            gid = if range_offset.zero?
              (codepoint + delta) & 0xFFFF
            else
              glyph = u16(range_offset_pos + range_offset + (codepoint - first) * 2)
              glyph.zero? ? 0 : (glyph + delta) & 0xFFFF
            end
            map[codepoint] = gid unless gid.zero?
          end
        end
        map
      end

      def parse_cmap_format12(offset)
        map = {}
        u32(offset + 12).times do |i|
          group = offset + 16 + i * 12
          first = u32(group)
          last = u32(group + 4)
          gid = u32(group + 8)
          (first..last).each { |codepoint| map[codepoint] = gid + codepoint - first }
        end
        map
      end

      def parse_post
        if (t = table_offset("post"))
          @italic_angle = i16(t + 4) + u16(t + 6) / 65536.0
          @underline_position = i16(t + 8)
          @underline_thickness = i16(t + 10)
          @fixed_pitch = u32(t + 12) != 0
        else
          @italic_angle = 0
          @underline_position = -@units_per_em / 10
          @underline_thickness = @units_per_em / 20
          @fixed_pitch = false
        end
      end

      def parse_os2
        if (t = table_offset("OS/2"))
          version = u16(t)
          @weight = u16(t + 4)
          @strikeout_size = i16(t + 26)
          @strikeout_position = i16(t + 28)
          if version >= 2
            @x_height = i16(t + 86)
            @cap_height = i16(t + 88)
          end
        end

        @weight ||= 400
        @strikeout_size ||= @underline_thickness
        @strikeout_position ||= (@ascender * 0.25).round
        @x_height ||= (@ascender * 0.5).round
        @cap_height ||= (@ascender * 0.7).round
      end

      def parse_name
        if (t = table_offset("name"))
          strings = t + u16(t + 4)
          u16(t + 2).times do |i|
            record = t + 6 + i * 12
            next unless u16(record + 6) == 6 # PostScript name

            platform = u16(record)
            raw = @data.byteslice(strings + u16(record + 10), u16(record + 8)).dup
            name = if platform == 1
              raw.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
            else
              raw.force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
            end
            @postscript_name = name.delete("^!-~").delete("[](){}<>/%#")
            break unless @postscript_name.empty?
          end
        end

        @postscript_name = "Font" if @postscript_name.nil? || @postscript_name.empty?
      end

      def build_font(tables)
        tags = tables.keys.sort
        entry_selector = Math.log2(tags.size).floor
        search_range = 2**entry_selector * 16

        directory = [0x00010000, tags.size, search_range, entry_selector, tags.size * 16 - search_range].pack("Nnnnn")
        body = String.new(encoding: Encoding::BINARY)
        body_offset = 12 + tags.size * 16
        head_offset = nil

        tags.each do |tag|
          data = tables[tag]
          head_offset = body_offset + body.bytesize if tag == "head"
          directory << [tag, checksum(data), body_offset + body.bytesize, data.bytesize].pack("a4NNN")
          body << data << padding(data)
        end

        font = directory << body
        font[head_offset + 8, 4] = [(0xB1B0AFBA - checksum(font)) & 0xFFFFFFFF].pack("N")
        font
      end

      def checksum(data)
        (data + padding(data)).unpack("N*").sum & 0xFFFFFFFF
      end
    end
  end
end
