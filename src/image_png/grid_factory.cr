module IntelQA::PNG
  class GridFactory(T)
    getter grid : Grid(T)

    def initialize(@ir : IR, decoder)
      @grid = @ir.interlace_method == 0 ? interlace_null(&decoder) : interlace_adam7(&decoder)
    end

    private def interlace_null(&decoder)
      grid = Grid(T).new @ir.width, @ir.height

      bpp = (@ir.bit_depth.clamp(8..) / 8 * IR::COLOR_TYPES[@ir.color_type][2]).to_i32
      scanline_width = (@ir.bit_depth.to_f / 8 * IR::COLOR_TYPES[@ir.color_type][2] * @ir.width).ceil.to_i32
      prior_scanline = nil
      decoded = Bytes.new scanline_width

      data_pos = 0
      @ir.height.times do |y|
        filter = @ir.data[data_pos]

        scanline = @ir.data[data_pos + 1, scanline_width]
        decoded = Filter.apply scanline, prior_scanline, decoded, bpp, filter

        data_pos += scanline_width + 1

        yield decoded, grid, y, @ir.bit_depth, @ir.palette

        if prior_scanline
          prior_scanline, decoded = decoded, prior_scanline
        else
          prior_scanline = decoded
          decoded = Bytes.new(scanline_width)
        end
      end

      grid
    end

    private def interlace_adam7(&decoder)
      starting_row = {0, 0, 4, 0, 2, 0, 1}
      starting_col = {0, 4, 0, 2, 0, 1, 0}
      row_increment = {8, 8, 8, 4, 4, 2, 2}
      col_increment = {8, 8, 4, 4, 2, 2, 1}

      pass = 0
      row = 0
      col = 0
      data_pos = 0

      grid = Grid(T).new(@ir.width, @ir.height)
      bpp = (@ir.bit_depth.clamp(8..) / 8 * IR::COLOR_TYPES[@ir.color_type][2]).to_i32

      while pass < 7
        prior_scanline = nil
        row = starting_row[pass]

        scanline_width_ = ((@ir.width - starting_col[pass]).to_f / col_increment[pass]).ceil.clamp(0..)
        scanline_width = (@ir.bit_depth.to_f / 8 * IR::COLOR_TYPES[@ir.color_type][2] * scanline_width_).ceil.to_i32

        if scanline_width_ == 0
          pass += 1
          next
        end

        decoded = Bytes.new(scanline_width)

        while row < @ir.height
          filter = @ir.data[data_pos]

          scanline = @ir.data[data_pos + 1, scanline_width]
          decoded = Filter.apply(scanline, prior_scanline, decoded, bpp, filter)

          data_pos += scanline_width + 1

          # TODO: This is definitely not the best way to do this
          # because so many intermediate canvases are created.
          # (Should not matter that much, because adam7 encoded @ir should be pretty rare)

          col = starting_col[pass]

          line_width = scanline_width_.to_i32
          line_canvas = Grid(T).new(line_width, 1)

          yield decoded, grid, 0, @ir.bit_depth, @ir.palette

          (0...line_width).each do |x|
            grid[col, row] = line_canvas[x, 0]
            col += col_increment[pass]
          end

          row += row_increment[pass]

          if prior_scanline
            prior_scanline, decoded = decoded, prior_scanline
          else
            prior_scanline = decoded
            decoded = Bytes.new(scanline_width)
          end
        end
        pass += 1
      end

      grid
    end

  end
end
