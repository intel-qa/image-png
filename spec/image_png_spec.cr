require "./spec_helper"

include IntelQA::PNG

BASIC_FORMATS_DIR = "./spec/data/basic_formats"

describe IntelQA::PNG do
  describe ".valid?" do
    it "informs if the given file is a valid png image" do
      valid?("./spec/data/text_files/short.txt").should be_false
      valid?("./spec/data/text_files/long.txt").should be_false
      valid?("./spec/data/basic_formats/basn0g01.png").should be_true
    end
  end

  describe ".metadata" do
    Dir.open BASIC_FORMATS_DIR do |d|
      d.children.each do |file|
        if valid? "#{BASIC_FORMATS_DIR}/#{file}"
          it "fetches PNG metadata for #{file}" do
            metadata("#{BASIC_FORMATS_DIR}/#{file}").tap do |md|
              md[:color_type].should eq file[4].to_i
              md[:palette].should eq(file[5] == 'p')
              md[:bit_depth].should eq file[6..7].to_i
            end
          end
        end
      end
    end
  end

  describe ".read(String)" do
    Dir.open BASIC_FORMATS_DIR do |d|
      d.children.each do |file|
        if valid? "#{BASIC_FORMATS_DIR}/#{file}"
          it "reads the PNG file #{file} into grid with correct pixel type" do
            read("#{BASIC_FORMATS_DIR}/#{file}").tap do |grid|
              case file[4].to_i
              when 0 then grid.pixel_type.should eq :grayscale
              when 2 then grid.pixel_type.should eq :rgb
              when 3 then grid.pixel_type.should eq :rgb_alpha
              when 4 then grid.pixel_type.should eq :grayscale_alpha
              when 6 then grid.pixel_type.should eq :rgb_alpha
              end
            end
          end
        end
      end
    end

    #TODO: write specs for stumpy_png/spec/png_suite_spec.cr
    #TODO: write specs for stumpy_png/spec/api_spec.cr
  end

  describe ".write(String)" do

    test_examples = [
      {
        filename: "basn0g16",
        bit_depth: 16,
        color_type: :grayscale
      },
      {
        filename: "basn4a16",
        bit_depth: 16,
        color_type: :grayscale_alpha
      },
      {
        filename: "basn2c16",
        bit_depth: 16,
        color_type: :rgb
      },
      {
        filename: "basn6a16",
        bit_depth: 16,
        color_type: :rgb_alpha
      },
      {
        filename: "basn0g08",
        bit_depth: 8,
        color_type: :grayscale
      },
      {
        filename: "basn4a08",
        bit_depth: 8,
        color_type: :grayscale_alpha
      },
      {
        filename: "basn2c08",
        bit_depth: 8,
        color_type: :rgb
      },
      {
        filename: "basn6a08",
        bit_depth: 8,
        color_type: :rgb_alpha
      },
    ]

    test_examples.each do |te|
      it "writes #{te[:bit_depth]} bit #{te[:color_type]}" do
        image = "./spec/data/basic_formats/#{te[:filename]}.png"
        tmp_image = "./tmp.png"

        original = read image
        write original, tmp_image, te[:bit_depth]

        written = read tmp_image

        case te[:color_type]
        when :grayscale       then original.should eq written.as(Grid(G))
        when :grayscale_alpha then original.should eq written.as(Grid(GA))
        when :rgb             then original.should eq written.as(Grid(RGB))
        when :rgb_alpha       then original.should eq written.as(Grid(RGBA))
        end
      end
    end
  end

end
