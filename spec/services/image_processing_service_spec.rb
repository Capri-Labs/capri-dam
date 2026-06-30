# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImageProcessingService, type: :service do
  let(:test_image_path) do
    # Use a real test image from fixtures
    Rails.root.join('spec/fixtures/images/test-image.jpg').to_s
  end

  before(:all) do
    # Create a minimal test image if it doesn't exist
    fixtures_dir = Rails.root.join('spec/fixtures/images')
    FileUtils.mkdir_p(fixtures_dir) unless Dir.exist?(fixtures_dir)

    unless File.exist?(Rails.root.join('spec/fixtures/images/test-image.jpg'))
      require 'mini_magick'
      # Create a simple valid JPEG image
      img = MiniMagick::Image.create do |convert|
        convert.size '200x200'
        convert << 'xc:blue'
      end
      img.format('jpg')
      img.write(Rails.root.join('spec/fixtures/images/test-image.jpg'))
    end
  end

  describe '#initialize' do
    it 'initializes with a valid source file' do
      service = described_class.new(test_image_path)
      expect(service.source_path).to eq(test_image_path)
    end

    it 'raises ValidationError for non-existent file' do
      expect do
        described_class.new('/nonexistent/path/image.jpg')
      end.to raise_error(ImageProcessingService::ValidationError, /does not exist/)
    end

    it 'raises ValidationError for unreadable file' do
      unreadable_path = Rails.root.join('tmp/unreadable_image.jpg').to_s
      File.write(unreadable_path, 'test')
      File.chmod(0o000, unreadable_path)

      expect do
        described_class.new(unreadable_path)
      end.to raise_error(ImageProcessingService::ValidationError, /not readable/)

      File.chmod(0o644, unreadable_path)
      File.delete(unreadable_path)
    end
  end

  describe '#process' do
    let(:service) { described_class.new(test_image_path) }

    it 'processes image and returns output path' do
      output = service.process({})
      expect(output).to be_a(String)
      expect(File.exist?(output)).to be true
      File.delete(output) if File.exist?(output)
    end

    describe 'brightness adjustment' do
      it 'applies positive brightness' do
        output = service.process({ brightness: 20 })
        expect(output).to be_a(String)
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'applies negative brightness' do
        output = service.process({ brightness: -30 })
        expect(output).to be_a(String)
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'validates brightness range' do
        expect do
          service.process({ brightness: 150 })
        end.to raise_error(ImageProcessingService::ValidationError, /brightness.*between/)
      end
    end

    describe 'contrast adjustment' do
      it 'applies contrast adjustment' do
        output = service.process({ contrast: 25 })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'validates contrast range' do
        expect do
          service.process({ contrast: -150 })
        end.to raise_error(ImageProcessingService::ValidationError)
      end
    end

    describe 'saturation adjustment' do
      it 'applies saturation adjustment' do
        output = service.process({ saturation: 30 })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'reduces saturation' do
        output = service.process({ saturation: -50 })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end
    end

    describe 'warmth adjustment' do
      it 'warms image' do
        output = service.process({ warmth: 40 })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'cools image' do
        output = service.process({ warmth: -40 })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end
    end

    describe 'rotation' do
      it 'rotates image 90 degrees' do
        output = service.process({ rotation: 90 })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'rotates image -90 degrees' do
        output = service.process({ rotation: -90 })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'validates rotation is divisible by 90' do
        expect do
          service.process({ rotation: 45 })
        end.to raise_error(ImageProcessingService::ValidationError, /divisible by 90/)
      end
    end

    describe 'flip adjustments' do
      it 'flips image horizontally' do
        output = service.process({ flip_horizontal: true })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'flips image vertically' do
        output = service.process({ flip_vertical: true })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'flips both directions' do
        output = service.process({ flip_horizontal: true, flip_vertical: true })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end
    end

    describe 'focal point' do
      it 'validates focal point coordinates' do
        expect do
          service.process({ focal_point: { x: 150, y: 50 } })
        end.to raise_error(ImageProcessingService::ValidationError, /focal_point x/)
      end

      it 'accepts valid focal point' do
        output = service.process({ focal_point: { x: 25, y: 75 } })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end
    end

    describe 'vignette effect' do
      it 'applies vignette' do
        output = service.process({ vignette: 50 })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'validates vignette range' do
        expect do
          service.process({ vignette: 150 })
        end.to raise_error(ImageProcessingService::ValidationError, /vignette/)
      end
    end

    describe 'filters' do
      it 'applies Vivid filter' do
        output = service.process({ filter: 'Vivid' })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'applies West filter' do
        output = service.process({ filter: 'West' })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'handles None filter' do
        output = service.process({ filter: 'None' })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'validates filter name' do
        expect do
          service.process({ filter: 'InvalidFilter' })
        end.to raise_error(ImageProcessingService::ValidationError, /filter/)
      end
    end

    describe 'crop aspect' do
      it 'accepts valid crop aspects' do
        %w[free 1:1 16:9 4:3 3:2 21:9].each do |aspect|
          expect do
            service.process({ crop_aspect: aspect })
          end.not_to raise_error
        end
      end

      it 'validates crop aspect' do
        expect do
          service.process({ crop_aspect: 'invalid' })
        end.to raise_error(ImageProcessingService::ValidationError, /crop_aspect/)
      end
    end

    describe 'output format' do
      it 'outputs as JPEG' do
        output = service.process({}, output_format: 'jpeg')
        expect(output).to end_with('.jpeg')
        File.delete(output) if File.exist?(output)
      end

      it 'outputs as PNG' do
        output = service.process({}, output_format: 'png')
        expect(output).to end_with('.png')
        File.delete(output) if File.exist?(output)
      end

      it 'validates output format' do
        expect do
          service.process({}, output_format: 'invalid')
        end.to raise_error(ImageProcessingService::ValidationError, /Output format/)
      end
    end

    describe 'quality parameter' do
      it 'validates quality range' do
        expect do
          service.process({}, quality: 150)
        end.to raise_error(ImageProcessingService::ValidationError, /Quality/)
      end

      it 'accepts valid quality values' do
        output = service.process({}, quality: 85)
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end
    end

    describe 'combined adjustments' do
      it 'applies multiple adjustments' do
        adjustments = {
          brightness: 15,
          contrast: -10,
          saturation: 25,
          rotation: 90,
          flip_horizontal: true,
          vignette: 30,
        }
        output = service.process(adjustments)
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'applies brightness, contrast, and saturation together' do
        output = service.process({
          brightness: 20,
          contrast: 15,
          saturation: 30,
        })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end
    end

    describe 'custom CLI' do
      it 'injects custom ImageMagick commands' do
        output = service.process({ custom_cli: '-modulate 120,100,100' })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'handles multiple custom commands' do
        output = service.process({ custom_cli: '-modulate 120,100,100 -quality 85' })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end

      it 'ignores empty custom CLI' do
        output = service.process({ custom_cli: '' })
        expect(File.exist?(output)).to be true
        File.delete(output) if File.exist?(output)
      end
    end

    describe 'error handling' do
      it 'handles ImageMagick errors gracefully' do
        allow_any_instance_of(MiniMagick::Image).to receive(:combine_options).and_raise(MiniMagick::Error, 'ImageMagick error')

        expect do
          service.process({})
        end.to raise_error(ImageProcessingService::ProcessingError, /Image processing failed/)
      end
    end
  end

  describe 'VALID_CROP_ASPECTS' do
    it 'includes standard aspect ratios' do
      expect(described_class::VALID_CROP_ASPECTS).to include(
        'free', '1:1', '16:9', '4:3', '3:2', '21:9'
      )
    end
  end

  describe 'FILTERS' do
    it 'includes standard filters' do
      expect(described_class::FILTERS).to include(
        'None', 'Vivid', 'West', 'Palma', 'Metro', 'Eiffel', 'Blush', 'Modena', 'Vogue'
      )
    end

    it 'all filters have operations array' do
      described_class::FILTERS.each do |name, config|
        expect(config).to have_key(:operations)
        expect(config[:operations]).to be_an(Array)
      end
    end
  end
end
