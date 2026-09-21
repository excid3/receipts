# frozen_string_literal: true

require "test_helper"

class TestPDF < Minitest::Test
  FONT = Receipts::PDF::Document::DEFAULT_FONT[:normal]
  LOGO = File.expand_path("../examples/images/logo.png", __dir__)

  def test_renders_valid_cross_reference_table
    pdf = Receipts::Receipt.new(receipt_attributes).render

    assert pdf.start_with?("%PDF-1.7")
    assert pdf.end_with?("%%EOF\n")

    startxref = pdf[/startxref\n(\d+)/, 1].to_i
    assert pdf.byteslice(startxref, 4) == "xref"

    offsets = pdf.byteslice(startxref, pdf.bytesize).scan(/^(\d{10}) 00000 n $/).flatten.map(&:to_i)
    refute_empty offsets
    offsets.each_with_index do |offset, index|
      assert_match(/\A#{index + 1} 0 obj\n/, pdf.byteslice(offset, 20))
    end
  end

  def test_renders_greek_and_cyrillic_names
    names = ["Дмитрий Шостакович", "Αλέξανδρος Παπαδόπουλος", "Łukasz Żółć", "Nguyễn Văn Thành"]
    pdf = Receipts::Receipt.new(receipt_attributes(recipient: names)).render
    to_unicode = inflated_streams(pdf).select { |stream| stream.include?("beginbfchar") }.join

    names.join.each_char.uniq.each do |char|
      hex = char.encode("UTF-16BE").unpack1("H*").upcase
      assert_includes to_unicode, "<#{hex}>", "missing ToUnicode mapping for #{char}"
    end
  end

  def test_bundled_font_covers_latin_greek_and_cyrillic
    ttf = Receipts::PDF::TrueType.load(FONT)
    "AZaz0123456789ÀÿĀžΑΩαωЀӿ€—“”".each_char do |char|
      refute_equal 0, ttf.glyph_id(char.ord), "missing glyph for #{char}"
    end
  end

  def test_font_subset_is_valid_true_type
    ttf = Receipts::PDF::TrueType.load(FONT)
    gids = "Hello Ωμέγα Щ".each_char.map { |c| ttf.glyph_id(c.ord) }
    data, mapping = ttf.subset(gids)
    tables = data.unpack1("x4n").times.map { |i| data.byteslice(12 + i * 16, 16).unpack("a4x4NN") }.to_h { |tag, offset, length| [tag, data.byteslice(offset, length)] }
    num_glyphs = tables["maxp"].unpack1("x4n")
    advances = tables["hmtx"].unpack("n*").each_slice(2).map(&:first)

    assert_equal mapping.size, num_glyphs
    assert_equal (0...mapping.size).to_a, mapping.values.sort
    gids.each { |gid| assert_equal ttf.advance(gid), advances[mapping.fetch(gid)] }
    assert_equal 0xB1B0AFBA, data.unpack("N*").sum & 0xFFFFFFFF
    assert_operator data.bytesize, :<, File.size(FONT) / 4
  end

  def test_rejects_cff_fonts
    assert_raises(Receipts::PDF::UnsupportedFontError) { Receipts::PDF::TrueType.new("OTTO" + "\0" * 100) }
  end

  def test_custom_default_font
    Receipts.default_font = {normal: FONT, bold: Receipts::PDF::Document::DEFAULT_FONT[:bold]}
    assert Receipts::Receipt.new(receipt_attributes).render.start_with?("%PDF")
  ensure
    Receipts.default_font = nil
  end

  def test_unknown_font
    error = assert_raises(ArgumentError) { Receipts::Receipt.new.text("hi", font: "Missing") }
    assert_match(/unknown font/, error.message)
  end

  def test_inline_format
    fragments = Receipts::PDF::InlineFormat.parse(
      "a <b>b <i>bi</i></b> <color rgb='#ff0000'>red</color> <link href=\"https://x.io\">link</link>&lt;<br/><x>"
    )

    assert_equal ["a ", "b ", "bi", " ", "red", " ", "link", "<", "\n", "<x>"], fragments.map { |f| f[:text] }
    assert_equal [:bold, :italic], fragments[2][:styles]
    assert_equal "ff0000", fragments[4][:color]
    assert_equal "https://x.io", fragments[6][:link]
    assert_nil fragments[7][:styles]
  end

  def test_text_wraps_at_spaces
    doc = Receipts::PDF::Document.new
    lines = doc.text_lines("one two three four", {size: 10}, doc.width_of("three four", size: 10) + 1)
    assert_equal ["one two", "three four"], lines.map { |line| line.runs.map(&:text).join }
  end

  def test_long_words_are_broken
    doc = Receipts::PDF::Document.new
    lines = doc.text_lines("x" * 50, {size: 10}, doc.width_of("x" * 10, size: 10) + 0.1)
    assert_equal ["x" * 10] * 5, lines.map { |line| line.runs.first.text }
  end

  def test_table_columns_share_extra_width_evenly
    doc = Receipts::PDF::Document.new
    table = Receipts::PDF::Table.new(doc, [["a", "bbbbbbbbbb"]], width: 400)
    narrow, wide = table.column_widths

    assert_in_delta 400, narrow + wide, 0.01
    assert_in_delta wide - narrow, doc.width_of("bbbbbbbbbb") - doc.width_of("a"), 0.01
  end

  def test_table_wraps_wide_columns
    doc = Receipts::PDF::Document.new
    table = Receipts::PDF::Table.new(doc, [["Label", "long " * 100]])
    label, value = table.column_widths

    assert_in_delta doc.bounds.width, label + value, 0.01
    assert_in_delta doc.width_of("Label") + 10, label, 0.01
  end

  def test_table_column_widths_option
    doc = Receipts::PDF::Document.new
    table = Receipts::PDF::Table.new(doc, [["a", "b", "c"]], width: 300, column_widths: [100, nil, 50])
    assert_equal [100, 150, 50], table.column_widths.map(&:round)
  end

  def test_long_tables_break_across_pages
    items = [["Item", "Amount"]] + Array.new(100) { |i| ["Item #{i}", "$#{i}"] }
    receipt = Receipts::Receipt.new(receipt_attributes(line_items: items))
    assert_operator receipt.page_count, :>, 1
  end

  def test_png_with_transparent_palette
    writer = Receipts::PDF::Writer.new
    image = Receipts::PDF::Image.load(LOGO)
    image.build(writer)
    dictionary = writer.instance_variable_get(:@objects).last.dictionary

    assert_equal [374, 51], [image.width, image.height]
    assert_equal :Indexed, dictionary[:ColorSpace].first
    assert_kind_of Receipts::PDF::Reference, dictionary[:SMask]
  end

  def test_png_with_alpha_channel
    png = png_file(color_type: 6, pixels: [255, 0, 0, 128, 0, 255, 0, 255])
    writer = Receipts::PDF::Writer.new
    Receipts::PDF::Image.load(StringIO.new(png)).build(writer)
    mask, image = writer.instance_variable_get(:@objects).last(2)

    assert_equal [255, 0, 0, 0, 255, 0].pack("C*"), Zlib::Inflate.inflate(image.data)
    assert_equal [128, 255].pack("C*"), Zlib::Inflate.inflate(mask.data)
  end

  def test_repeated_images_are_embedded_once
    doc = Receipts::PDF::Document.new
    2.times { doc.image LOGO, height: 16 }
    pdf = doc.render

    assert_equal 2, pdf.scan("/Subtype /Image").size # the image and its transparency mask
    assert_equal 2, inflated_streams(pdf).join.scan("/I1 Do").size
    assert_same Receipts::PDF::Image.load(LOGO), Receipts::PDF::Image.load(File.open(LOGO, "rb"))
  end

  def test_jpeg_dimensions
    jpeg = "\xFF\xD8\xFF\xE0\x00\x04\x00\x00\xFF\xC0\x00\x11\x08\x00\x20\x00\x40\x03".b + "\0" * 20
    image = Receipts::PDF::Image.load(StringIO.new(jpeg))
    assert_equal [64, 32], [image.width, image.height]
  end

  def test_rejects_unknown_image_formats
    assert_raises(Receipts::PDF::UnsupportedImageError) { Receipts::PDF::Image.load(StringIO.new("GIF89a")) }
  end

  private

  def receipt_attributes(overrides = {})
    {
      company: {name: "Company", address: "123 Street", email: "company@example.org", logo: LOGO},
      recipient: ["Customer"],
      details: [["Receipt", "123"]],
      line_items: [["<b>Item</b>", "<b>Amount</b>"], ["Product", "$10"]]
    }.merge(overrides)
  end

  def inflated_streams(pdf)
    pdf.scan(/stream\n(.*?)\nendstream/m).flatten.map do |data|
      Zlib::Inflate.inflate(data)
    rescue Zlib::Error
      ""
    end
  end

  # A single row PNG with no filtering
  def png_file(color_type:, pixels:)
    width = pixels.size / {2 => 3, 6 => 4}.fetch(color_type)
    chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    Receipts::PDF::Image::PNG_SIGNATURE +
      chunk.call("IHDR", [width, 1, 8, color_type, 0, 0, 0].pack("NNCCCCC")) +
      chunk.call("IDAT", Zlib::Deflate.deflate(([0] + pixels).pack("C*"))) +
      chunk.call("IEND", "")
  end
end
