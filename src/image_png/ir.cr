require "./helper"
require "./datastream"
require "./filters"
require "./scanline"

module IntelQA::PNG
  class IR
    # { name, valid bit depths, "fields" per pixel }
    COLOR_TYPES = {
      0 => {:grayscale, {1, 2, 4, 8, 16}, 1},
      2 => {:rgb, {8, 16}, 3},
      3 => {:palette, {1, 2, 4, 8}, 1},
      4 => {:grayscale_alpha, {8, 16}, 2},
      6 => {:rgb_alpha, {8, 16}, 4},
    }

    INTERLACE_METHODS = {
      0 => :no_interlace,
      1 => :adam7,
    }

    getter width = 0_i32
    getter height = 0_i32
    getter bit_depth = 0_u8
    getter color_type = 0_u8
    getter compression_method = 0_u8
    getter filter_method = 0_u8
    getter interlace_method = 0_u8
    getter palette = [] of RGBA
    getter? parsed = false
    getter data = Bytes.new(0)
    # getter canvas = Canvas(RGBA).new(0, 0)

    def initialize
      @idat_buffer = IO::Memory.new
      @idat_count = 0
    end

    def parse_iend(chunk : Chunk)
      raise "Missing IDAT chunk" if @idat_count == 0

      # Reset buffer position
      @idat_buffer.pos = 0

      Compress::Zlib::Reader.open(@idat_buffer) do |inflate|
        io = IO::Memory.new
        IO.copy(inflate, io)
        @data = io.to_slice
      end

      @parsed = true
    end

    def parse_idat(chunk : Chunk)
      @idat_count += 1
      @idat_buffer.write(chunk.data)
    end

    def parse_plte(chunk : Chunk)
      raise "Invalid palette length" unless (chunk.size % 3) == 0
      @palette = chunk.data.each_slice(3).map { |rgb|
        r, g, b = rgb
        RGBA.from_rgb_n(r, g, b, 8)
      }.to_a
    end

    def parse_ihdr(chunk : Chunk)
      @width = Helper.parse_integer(chunk.data[0, 4])
      @height = Helper.parse_integer(chunk.data[4, 4])

      @color_type = chunk.data[9]
      color_type = COLOR_TYPES[@color_type]?
      color_type ||
        raise "Invalid color type"

      @bit_depth = chunk.data[8]
      @bit_depth.in?(color_type[1]) ||
        raise "Invalid bit depth for this color type"

      @compression_method = chunk.data[10]
      compression_method.zero? ||
        raise "Invalid compression method"

      @filter_method = chunk.data[11]
      filter_method.zero? ||
        raise "Invalid filter method"

      @interlace_method = chunk.data[12]
      INTERLACE_METHODS.has_key?(interlace_method) ||
        raise "Invalid interlace method"
    end

    def parse_chunk(chunk)
      case chunk.type
      when "IHDR" then parse_ihdr(chunk)
      when "PLTE" then parse_plte(chunk)
      when "IDAT" then parse_idat(chunk)
      when "IEND" then parse_iend(chunk)
      end
    end
  end
end
