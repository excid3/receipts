require "zlib"
require "digest/md5"

module Receipts
  module PDF
    # An indirect object reference: `12 0 R`
    Reference = Struct.new(:id)

    # A string written in hex form: `<48656C6C6F>`
    HexString = Struct.new(:bytes)

    class Stream
      attr_reader :dictionary, :data

      # Data is Flate compressed unless the dictionary already declares a filter
      def initialize(data, dictionary = {})
        data = data.b
        dictionary = dictionary.dup

        unless dictionary.key?(:Filter)
          data = Zlib::Deflate.deflate(data)
          dictionary[:Filter] = :FlateDecode
        end

        dictionary[:Length] = data.bytesize
        @data = data
        @dictionary = dictionary
      end
    end

    # Serializes Ruby values into PDF syntax
    module Serializer
      NAME_ESCAPE = /[^\x21-\x7E]|[#%()\/<>\[\]{}]/n

      module_function

      def dump(value)
        case value
        when Reference then "#{value.id} 0 R"
        when Symbol then name(value)
        when Hash then "<<" + value.map { |k, v| "#{name(k)} #{dump(v)}" }.join(" ") + ">>"
        when Array then "[" + value.map { |v| dump(v) }.join(" ") + "]"
        when HexString then "<#{value.bytes.unpack1("H*")}>"
        when String then literal(value)
        when Integer then value.to_s
        when Float then number(value)
        when true, false then value.to_s
        when nil then "null"
        else raise ArgumentError, "cannot serialize #{value.class} to PDF"
        end
      end

      def name(value)
        "/" + value.to_s.b.gsub(NAME_ESCAPE) { |c| format("#%02X", c.ord) }
      end

      def literal(value)
        "(" + value.b.gsub(/[\\()\r]/n) { |c| (c == "\r") ? "\\r" : "\\#{c}" } + ")"
      end

      def number(value)
        return value.to_s if value.is_a?(Integer)
        str = format("%.4f", value).sub(/\.?0+\z/, "")
        (str == "-0") ? "0" : str
      end

      # Text strings (document info, etc) must be PDFDocEncoding or UTF-16BE with a BOM
      def text_string(value)
        value = value.to_s
        value.ascii_only? ? value.b : "\xFE\xFF".b + value.encode("UTF-16BE").b
      end
    end

    # Assembles numbered objects into a PDF file with a cross-reference table
    class Writer
      def initialize
        @objects = []
      end

      def reserve
        @objects << nil
        Reference.new(@objects.size)
      end

      def set(ref, value)
        @objects[ref.id - 1] = value
        ref
      end

      def add(value)
        set(reserve, value)
      end

      def render(root:, info:)
        out = "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n".b

        offsets = @objects.each_with_index.map do |object, index|
          offset = out.bytesize
          out << "#{index + 1} 0 obj\n"
          if object.is_a?(Stream)
            out << Serializer.dump(object.dictionary) << "\nstream\n" << object.data << "\nendstream"
          else
            out << Serializer.dump(object)
          end
          out << "\nendobj\n"
          offset
        end

        xref = out.bytesize
        id = HexString.new(Digest::MD5.digest(out))

        out << "xref\n0 #{@objects.size + 1}\n0000000000 65535 f \n"
        offsets.each { |offset| out << format("%010d 00000 n \n", offset) }
        out << "trailer\n" << Serializer.dump(Size: @objects.size + 1, Root: root, Info: info, ID: [id, id])
        out << "\nstartxref\n#{xref}\n%%EOF\n"
      end
    end
  end
end
