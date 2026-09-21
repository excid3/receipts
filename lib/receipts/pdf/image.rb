module Receipts
  module PDF
    class UnsupportedImageError < StandardError; end

    module Image
      PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b

      # Recently used images, keyed by content, so a logo used on every receipt is only decoded once
      CACHE = {}
      CACHE_MUTEX = Mutex.new
      CACHE_SIZE = 16

      # Accepts a path, Pathname, or IO-like object
      def self.load(source)
        data = if source.respond_to?(:read)
          source.binmode if source.respond_to?(:binmode)
          source.rewind if source.respond_to?(:rewind)
          source.read
        else
          File.binread(source.to_s)
        end.b

        key = Digest::MD5.digest(data)
        CACHE_MUTEX.synchronize do
          CACHE[key] ||= parse(data)
          CACHE.shift while CACHE.size > CACHE_SIZE
          CACHE[key]
        end
      end

      def self.parse(data)
        if data.start_with?("\xFF\xD8".b)
          JPEG.new(data)
        elsif data.start_with?(PNG_SIGNATURE)
          PNG.new(data)
        else
          raise UnsupportedImageError, "only PNG and JPEG images are supported"
        end
      end

      def self.xobject(width, height, color_space, bits)
        {Type: :XObject, Subtype: :Image, Width: width, Height: height, ColorSpace: color_space, BitsPerComponent: bits}
      end

      class JPEG
        START_OF_FRAME = [0xC0..0xC3, 0xC5..0xC7, 0xC9..0xCB, 0xCD..0xCF].freeze
        COLOR_SPACES = {1 => :DeviceGray, 3 => :DeviceRGB, 4 => :DeviceCMYK}.freeze

        attr_reader :width, :height

        def initialize(data)
          @data = data
          pos = 2

          while pos + 4 <= data.bytesize
            raise UnsupportedImageError, "invalid JPEG image" unless data.getbyte(pos) == 0xFF
            marker = data.getbyte(pos + 1)
            if marker == 0xFF # fill byte
              pos += 1
              next
            end

            length = data.byteslice(pos + 2, 2).unpack1("n")
            @adobe = true if marker == 0xEE && data.byteslice(pos + 4, 5) == "Adobe"

            if START_OF_FRAME.any? { |range| range.cover?(marker) }
              @bits, @height, @width, @components = data.byteslice(pos + 4, 6).unpack("CnnC")
              break
            end

            pos += 2 + length
          end

          raise UnsupportedImageError, "invalid JPEG image" unless @width
          raise UnsupportedImageError, "unsupported JPEG color components: #{@components}" unless COLOR_SPACES.key?(@components)
        end

        def build(writer)
          dictionary = Image.xobject(@width, @height, COLOR_SPACES.fetch(@components), @bits).merge(Filter: :DCTDecode)
          # Adobe CMYK JPEGs store inverted values
          dictionary[:Decode] = [1, 0] * 4 if @components == 4 && @adobe
          writer.add(Stream.new(@data, dictionary))
        end
      end

      class PNG
        CHANNELS = {0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4}.freeze

        attr_reader :width, :height

        def initialize(data)
          @idat = String.new(encoding: Encoding::BINARY)
          pos = PNG_SIGNATURE.bytesize

          while pos + 8 <= data.bytesize
            length, type = data.byteslice(pos, 8).unpack("Na4")
            chunk = data.byteslice(pos + 8, length)

            case type
            when "IHDR" then @width, @height, @bit_depth, @color_type, _, _, @interlace = chunk.unpack("NNCCCCC")
            when "PLTE" then @palette = chunk
            when "tRNS" then @transparency = chunk
            when "IDAT" then @idat << chunk
            when "IEND" then break
            end

            pos += 12 + length
          end

          raise UnsupportedImageError, "invalid PNG image" unless @width && CHANNELS.key?(@color_type)
          raise UnsupportedImageError, "interlaced PNG images are not supported" if @interlace == 1
        end

        def build(writer)
          if @color_type == 4 || @color_type == 6
            dictionary = Image.xobject(@width, @height, color_space, 8).merge(Filter: :FlateDecode, SMask: soft_mask(writer))
            return writer.add(Stream.new(decoded[:color], dictionary))
          end

          # Compressed PNG data can be embedded directly using the PNG predictor
          dictionary = Image.xobject(@width, @height, color_space, @bit_depth).merge(
            Filter: :FlateDecode,
            DecodeParms: {Predictor: 15, Colors: CHANNELS[@color_type], BitsPerComponent: @bit_depth, Columns: @width}
          )

          if @transparency && @color_type == 3
            dictionary[:SMask] = soft_mask(writer)
          elsif @transparency
            # Color key masking: [min max] per channel
            dictionary[:Mask] = @transparency.unpack("n*").first(CHANNELS[@color_type]).flat_map { |v| [v, v] }
          end

          writer.add(Stream.new(@idat, dictionary))
        end

        private

        def color_space
          case @color_type
          when 0, 4 then :DeviceGray
          when 2, 6 then :DeviceRGB
          when 3 then [:Indexed, :DeviceRGB, @palette.bytesize / 3 - 1, HexString.new(@palette)]
          end
        end

        def soft_mask(writer)
          dictionary = Image.xobject(@width, @height, :DeviceGray, 8).merge(Filter: :FlateDecode)
          writer.add(Stream.new(decoded[:alpha], dictionary))
        end

        # Compressed color and alpha data, memoized since images are cached across documents
        def decoded
          @decoded ||= begin
            color, alpha = (@color_type == 3) ? [nil, palette_alpha] : split_alpha
            {color: color && Zlib::Deflate.deflate(color), alpha: Zlib::Deflate.deflate(alpha)}
          end
        end

        # Alpha channel for palette images from the per-palette-entry tRNS values
        def palette_alpha
          alphas = @transparency.bytes
          alpha = String.new(capacity: @width * @height, encoding: Encoding::BINARY)

          each_row(1, (@width * @bit_depth + 7) / 8) do |row|
            indexes = if @bit_depth == 8
              row
            else
              row.pack("C*").unpack1("B*").scan(/.{#{@bit_depth}}/).first(@width).map { |bits| bits.to_i(2) }
            end
            alpha << indexes.map { |index| alphas[index] || 255 }.pack("C*")
          end
          alpha
        end

        # Splits gray+alpha or RGBA pixels into color and alpha, reduced to 8 bits per sample
        def split_alpha
          channels = CHANNELS[@color_type]
          sample = @bit_depth / 8
          step = channels * sample
          # Positions of each sample's high byte within a row
          color_bytes = Array.new(@width) { |x| Array.new(channels - 1) { |c| x * step + c * sample } }.flatten
          alpha_bytes = Array.new(@width) { |x| x * step + (channels - 1) * sample }

          color = String.new(capacity: @width * @height * (channels - 1), encoding: Encoding::BINARY)
          alpha = String.new(capacity: @width * @height, encoding: Encoding::BINARY)
          each_row(step, @width * step) do |row|
            color << row.values_at(*color_bytes).pack("C*")
            alpha << row.values_at(*alpha_bytes).pack("C*")
          end
          [color, alpha]
        end

        # Decompresses the image data and reverses the per-row PNG filters, yielding each row's bytes
        def each_row(bpp, row_bytes)
          data = Zlib::Inflate.inflate(@idat)
          previous = Array.new(row_bytes, 0)

          @height.times do |y|
            pos = y * (row_bytes + 1)
            filter = data.getbyte(pos)
            row = data.byteslice(pos + 1, row_bytes).bytes

            case filter
            when 0
              nil
            when 1
              (bpp...row_bytes).each { |i| row[i] = (row[i] + row[i - bpp]) & 0xFF }
            when 2
              row_bytes.times { |i| row[i] = (row[i] + previous[i]) & 0xFF }
            when 3
              row_bytes.times do |i|
                left = (i >= bpp) ? row[i - bpp] : 0
                row[i] = (row[i] + ((left + previous[i]) >> 1)) & 0xFF
              end
            when 4
              row_bytes.times do |i|
                a = (i >= bpp) ? row[i - bpp] : 0
                b = previous[i]
                c = (i >= bpp) ? previous[i - bpp] : 0
                p = a + b - c
                pa = (p - a).abs
                pb = (p - b).abs
                pc = (p - c).abs
                predictor = if pa <= pb && pa <= pc
                  a
                else
                  (pb <= pc) ? b : c
                end
                row[i] = (row[i] + predictor) & 0xFF
              end
            else
              raise UnsupportedImageError, "invalid PNG filter type: #{filter}"
            end

            yield row
            previous = row
          end
        end
      end
    end
  end
end
