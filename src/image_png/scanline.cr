module IntelQA::PNG
  module Scanline
    extend self

    # We don't need to care about invalid bit depths here,
    # because they are validated before
    def decode_grayscale(scanline, grid : Grid(G), y, bit_depth)
      case bit_depth
      when  1 then Scanline.decode_grayscale_1(scanline, grid, y)
      when  2 then Scanline.decode_grayscale_2(scanline, grid, y)
      when  4 then Scanline.decode_grayscale_4(scanline, grid, y)
      when  8 then Scanline.decode_grayscale_8(scanline, grid, y)
      when 16 then Scanline.decode_grayscale_16(scanline, grid, y)
      end
    end

    def decode_grayscale_alpha(scanline, grid, y, bit_depth)
      if bit_depth == 8
        Scanline.decode_grayscale_alpha_8(scanline, grid, y)
      else
        Scanline.decode_grayscale_alpha_16(scanline, grid, y)
      end
    end

    def decode_rgb(scanline, grid, y, bit_depth)
      if bit_depth == 8
        Scanline.decode_rgb_8(scanline, grid, y)
      else
        Scanline.decode_rgb_16(scanline, grid, y)
      end
    end

    def decode_rgb_alpha(scanline, grid, y, bit_depth)
      if bit_depth == 8
        Scanline.decode_rgb_alpha_8(scanline, grid, y)
      else
        Scanline.decode_rgb_alpha_16(scanline, grid, y)
      end
    end

    def decode_palette(scanline, grid, y, bit_depth, palette)
      case bit_depth
      when 1 then Scanline.decode_palette_1(scanline, grid, y, palette)
      when 2 then Scanline.decode_palette_2(scanline, grid, y, palette)
      when 4 then Scanline.decode_palette_4(scanline, grid, y, palette)
      when 8 then Scanline.decode_palette_8(scanline, grid, y, palette)
      end
    end

    def decode_grayscale_1(scanline, grid, y)
      (0...grid.width).step(8).each do |x|
        byte = scanline[x // 8]
        (0...8).each do |x2|
          # Make sure we don't write invalid pixels
          # if the grid.width is not a multiple of 8
          break if x + x2 >= grid.width

          gray = (byte >> 7) == 0 ? 0_u16 : 0xffff_u16
          byte <<= 1
          grid[x + x2, y] = G.new(gray)
        end
      end
    end

    def decode_grayscale_2(scanline, grid, y)
      (0...grid.width).step(4).each do |x|
        byte = scanline[x // 4]
        (0...4).each do |x2|
          break if x + x2 >= grid.width

          gray = (byte >> 6).to_u16
          gray += gray << 2
          gray += gray << 4
          gray += gray << 8

          byte <<= 2
          grid[x + x2, y] = G.new(gray)
        end
      end
    end

    def decode_grayscale_4(scanline, grid, y)
      (0...grid.width).step(2).each do |x|
        byte = scanline[x // 2]
        (0...2).each do |x2|
          break if x + x2 >= grid.width

          gray = (byte >> 4).to_u16
          gray += gray << 4
          gray += gray << 8

          byte <<= 4
          grid[x + x2, y] = G.new(gray)
        end
      end
    end

    def decode_grayscale_8(scanline, grid, y)
      (0...grid.width).each do |x|
        gray = scanline[x].to_u16
        gray += gray << 8
        grid[x, y] = G.new(gray)
      end
    end

    def decode_grayscale_16(scanline, grid, y)
      (0...grid.width).each do |x|
        gray = (scanline[2 * x].to_u16 << 8) + scanline[2 * x + 1]
        grid[x, y] = G.new(gray)
      end
    end

    def decode_grayscale_alpha_8(scanline, grid, y)
      (0...grid.width).each do |x|
        start = 2 * x
        gray = scanline[start].to_u16
        gray += gray << 8
        alpha = scanline[start + 1].to_u16
        alpha += alpha << 8

        color = GA.new(gray, alpha)
        grid[x, y] = color
      end
    end

    def decode_grayscale_alpha_16(scanline, grid, y)
      (0...grid.width).each do |x|
        start = 4 * x
        gray = (scanline[start].to_u16 << 8) + scanline[start + 1]
        alpha = (scanline[start + 2].to_u16 << 8) + scanline[start + 3]
        grid[x, y] = GA.new(gray, alpha)
      end
    end

    def decode_rgb_8(scanline, grid, y)
      (0...grid.width).each do |x|
        start = x * 3
        red = scanline[start].to_u16
        red += red << 8
        green = scanline[start + 1].to_u16
        green += green << 8
        blue = scanline[start + 2].to_u16
        blue += blue << 8

        grid[x, y] = RGB.new(red, green, blue)
      end
    end

    def decode_rgb_16(scanline, grid, y)
      (0...grid.width).each do |x|
        start = x * 6
        red = (scanline[start].to_u16 << 8) + scanline[start + 1]
        green = (scanline[start + 2].to_u16 << 8) + scanline[start + 3]
        blue = (scanline[start + 4].to_u16 << 8) + scanline[start + 5]

        grid[x, y] = RGB.new(red, green, blue)
      end
    end

    def decode_rgb_alpha_8(scanline, grid, y)
      (0...grid.width).each do |x|
        start = x * 4
        red = (scanline[start].to_u16 << 8) + scanline[start]
        green = (scanline[start + 1].to_u16 << 8) + scanline[start + 1]
        blue = (scanline[start + 2].to_u16 << 8) + scanline[start + 2]
        alpha = (scanline[start + 3].to_u16 << 8) + scanline[start + 3]

        grid[x, y] = RGBA.new(red, green, blue, alpha)
      end
    end

    def decode_rgb_alpha_16(scanline, grid, y)
      (0...grid.width).each do |x|
        start = x * 8
        red = (scanline[start].to_u16 << 8) + scanline[start + 1]
        green = (scanline[start + 2].to_u16 << 8) + scanline[start + 3]
        blue = (scanline[start + 4].to_u16 << 8) + scanline[start + 5]
        alpha = (scanline[start + 6].to_u16 << 8) + scanline[start + 7]

        grid[x, y] = RGBA.new(red, green, blue, alpha)
      end
    end

    def decode_palette_1(scanline, grid, y, palette)
      (0...grid.width).step(8).each do |x|
        byte = scanline[x // 8]
        (0...8).each do |x2|
          break if x + x2 >= grid.width

          grid[x + x2, y] = palette[byte >> 7]
          byte <<= 1
        end
      end
    end

    def decode_palette_2(scanline, grid, y, palette)
      (0...grid.width).step(4).each do |x|
        byte = scanline[x // 4]
        (0...4).each do |x2|
          break if x + x2 >= grid.width

          grid[x + x2, y] = palette[byte >> 6]
          byte <<= 2
        end
      end
    end

    def decode_palette_4(scanline, grid, y, palette)
      (0...grid.width).step(2).each do |x|
        byte = scanline[x // 2]
        (0...2).each do |x2|
          break if x + x2 >= grid.width

          grid[x + x2, y] = palette[byte >> 4]
          byte <<= 4
        end
      end
    end

    def decode_palette_8(scanline, grid, y, palette)
      (0...grid.width).each do |x|
        byte = scanline[x]
        grid[x, y] = palette[byte]
      end
    end
  end
end
