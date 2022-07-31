require "image_carrier"
require "./image_png/ir"
require "./image_png/datastream"
require "./image_png/grid_factory"
require "./image_png/scanline"
require "./image_png/filters"
require "./image_png/crc_io"

include Image::Carrier

# TODO: Write documentation for `Image::Png`
module Image::PNG
  VERSION = "0.1.0"

  extend self

  HEADER = 0x89504e470d0a1a0a

  DECODERS = {
    grayscale:       ->Scanline.decode_grayscale(Bytes, Grid(G), Int32, UInt8),
    grayscale_alpha: ->Scanline.decode_grayscale_alpha(Bytes, Grid(GA), Int32, UInt8),
    rgb:             ->Scanline.decode_rgb(Bytes, Grid(RGB), Int32, UInt8),
    rgb_alpha:       ->Scanline.decode_rgb_alpha(Bytes, Grid(RGBA), Int32, UInt8),
    palette:         ->Scanline.decode_palette(Bytes, Grid(RGBA), Int32, UInt8, Array(RGBA)),
  }

  WRITE_BIT_DEPTHS  = {8, 16}

  PIXEL_COLOR_TYPES = {
    rgb:             2_u8,
    rgb_alpha:       6_u8,
    grayscale:       0_u8,
    grayscale_alpha: 4_u8,
  }

  COLOR_TYPES = {
    0 => :grayscale,
    2 => :rgb,
    3 => :palette,
    4 => :grayscale_alpha,
    6 => :rgb_alpha,
  }

  def valid?(path : String)
    begin
      File.open path, "rb" do |file|
        file.read_bytes(UInt64, IO::ByteFormat::BigEndian) == Image::PNG::HEADER
      end
    rescue IO::EOFError
      false
    end
  end

  def metadata(path : String)
    ir = File.open path, "rb" do |file|
      IR.new.tap do |ir|
        Datastream.read(file).chunks.each do |chunk|
          ir.parse_chunk chunk
        end
      end
    end

    metadata = {
      width: ir.width,
      height: ir.height,
      interlace_method: ir.interlace_method,
      color_type: ir.color_type,
      bit_depth: ir.bit_depth,
      compression_method: ir.compression_method,
      palette: !ir.palette.empty?,
      parsed: ir.parsed?,
    }
  end

  def color_type(path : String)
    COLOR_TYPES[metadata(path)[:color_type]]
  end

  def data(path : String)
    File.open path, "rb" do |file|
      IR.new.tap { |ir|
        Datastream.read(file).chunks.each do |chunk|
          ir.parse_chunk chunk
        end
      }.data
    end
  end

  def read(path : String)
    File.open path, "rb" do |file|
      read(file)
    end
  end

  def ir(io : IO)
    IR.new.tap do |ir|
      Datastream.read(io).chunks.each {|chunk| ir.parse_chunk chunk}
    end
  end

  def grid(ir : IR)
    grid = case ir.color_type
    when 0 then GridFactory(G).new(ir, DECODERS[:grayscale]).grid
    when 4 then GridFactory(GA).new(ir, DECODERS[:grayscale_alpha]).grid
    when 2 then GridFactory(RGB).new(ir, DECODERS[:rgb]).grid
    when 6 then GridFactory(RGBA).new(ir, DECODERS[:rgb_alpha]).grid
    when 3 then GridFactory(RGBA).new(ir, DECODERS[:palette]).grid
    end

    raise "Unknown color type" if grid.nil?
    grid
  end

  def read(io : IO)
    grid ir(io)
  end

  def write(grid, path : String, bit_depth)
    File.open path, "wb" do |file|
      write grid, file, bit_depth
    end
  end

  def write(grid, io : IO, bit_depth = 16)
    color_type = PIXEL_COLOR_TYPES[grid.pixel_type]
    raise "Invalid grid pixel type: #{grid.pixel_type}, options: #{PIXEL_COLOR_TYPES.keys.inspect}" if color_type.nil?

    raise "Invalid bit depth: #{bit_depth}, options: #{WRITE_BIT_DEPTHS.inspect}" unless WRITE_BIT_DEPTHS.includes? bit_depth

    io.write_bytes HEADER, IO::ByteFormat::BigEndian

    crc_io = CrcIO.new
    multi = IO::MultiWriter.new crc_io, io

    # Write the IHDR chunk
    io.write_bytes 13_u32, IO::ByteFormat::BigEndian
    multi << "IHDR"

    multi.write_bytes grid.width.to_u32, IO::ByteFormat::BigEndian
    multi.write_bytes grid.height.to_u32, IO::ByteFormat::BigEndian
    multi.write_byte bit_depth.to_u8
    multi.write_byte color_type
    multi.write_byte 0_u8 # compression = deflate
    multi.write_byte 0_u8 # filter = adaptive (only option)
    multi.write_byte 0_u8 # interlacing = none

    multi.write_bytes crc_io.crc.to_u32, IO::ByteFormat::BigEndian
    crc_io.reset

    # Write the IDAT chunk with a dummy chunk size
    io.write_bytes 0_u32, IO::ByteFormat::BigEndian
    multi << "IDAT"
    crc_io.size = 0

    Compress::Zlib::Writer.open multi do |deflate|
      case grid.pixel_type
      when :rgb_alpha       then write_rgb_alpha grid.as(Grid(RGBA)), deflate, bit_depth
      when :rgb             then write_rgb grid.as(Grid(RGB)), deflate, bit_depth
      when :grayscale_alpha then write_grayscale_alpha grid.as(Grid(GA)), deflate, bit_depth
      when :grayscale       then write_grayscale grid.as(Grid(G)), deflate, bit_depth
      end
    end

    # Go back and write the size
    io.seek -(4 + 4 + crc_io.size), IO::Seek::Current
    io.write_bytes crc_io.size.to_u32, IO::ByteFormat::BigEndian
    io.seek 0, IO::Seek::End
    multi.write_bytes crc_io.crc.to_u32, IO::ByteFormat::BigEndian

    # Write the IEND chunk
    io.write_bytes 0_u32, IO::ByteFormat::BigEndian
    multi << "IEND"
    multi.write_bytes Digest::CRC32.checksum("IEND"), IO::ByteFormat::BigEndian
  end

  private def write_rgb_alpha(grid, output, bit_depth)
    if bit_depth == 16
      buffer = Bytes.new(1 + grid.width * 8)
      grid.each_row do |col|
        buffer_ptr = buffer + 1 # The first byte is 0 => no filter
        col.each do |pixel|
          {pixel.r, pixel.g, pixel.b, pixel.a}.each do |value|
            IO::ByteFormat::BigEndian.encode value, buffer_ptr
            buffer_ptr += 2
          end
        end
        output.write buffer
      end
    else
      buffer = Bytes.new(1 + grid.width * 4)
      grid.each_row do |col|
        i = 1
        col.each do |pixel|
          {pixel.r, pixel.g, pixel.b, pixel.a}.each do |value|
            buffer[i] = (value >> 8).to_u8
            i += 1
          end
        end
        output.write buffer
      end
    end
  end

  private def write_rgb(grid, output, bit_depth)
    if bit_depth == 16
      buffer = Bytes.new(1 + grid.width * 6)
      grid.each_row do |col|
        buffer_ptr = buffer + 1 # The first byte is 0 => no filter
        col.each do |pixel|
          {pixel.r, pixel.g, pixel.b}.each do |value|
            IO::ByteFormat::BigEndian.encode value, buffer_ptr
            buffer_ptr += 2
          end
        end
        output.write buffer
      end
    else
      buffer = Bytes.new(1 + grid.width * 3)
      grid.each_row do |col|
        i = 1
        col.each do |pixel|
          {pixel.r, pixel.g, pixel.b}.each do |value|
            buffer[i] = (value >> 8).to_u8
            i += 1
          end
        end
        output.write buffer
      end
    end
  end

  private def write_grayscale_alpha(grid, output, bit_depth)
    if bit_depth == 16
      buffer = Bytes.new(1 + grid.width * 4)
      grid.each_row do |col|
        buffer_ptr = buffer + 1 # The first byte is 0 => no filter
        col.each do |pixel|
          {pixel.g, pixel.a}.each do |value|
            IO::ByteFormat::BigEndian.encode value, buffer_ptr
            buffer_ptr += 2
          end
        end
        output.write buffer
      end
    else
      buffer = Bytes.new(1 + grid.width * 2)
      grid.each_row do |col|
        i = 1
        col.each do |pixel|
          {pixel.g, pixel.a}.each do |value|
            buffer[i] = (value >> 8).to_u8
            i += 1
          end
        end
        output.write buffer
      end
    end
  end

  private def write_grayscale(grid, output, bit_depth)
    if bit_depth == 16
      buffer = Bytes.new(1 + grid.width * 2)
      grid.each_row do |col|
        buffer_ptr = buffer + 1 # The first byte is 0 => no filter
        col.each do |pixel|
          IO::ByteFormat::BigEndian.encode pixel.g, buffer_ptr
          buffer_ptr += 2
        end
        output.write buffer
      end
    else
      buffer = Bytes.new(1 + grid.width * 1)
      grid.each_row do |col|
        i = 1
        col.each do |pixel|
          gray = pixel.g
          buffer[i] = (gray >> 8).to_u8
          i += 1
        end
        output.write buffer
      end
    end
  end
end
