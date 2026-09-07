# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnnotationTarget, type: :model do
  let(:author) { create(:user) }
  let(:asset) { create(:asset, user: author) }
  let(:version) { create(:asset_version, asset: asset, version_number: 1) }
  let(:thread) { CommentThread.create!(asset: asset, origin_version: version, created_by: author) }
  let(:comment) { thread.comments.create!(body: 'Please review this region', author: author, asset_version: version) }

  def build_target(**attributes)
    described_class.new({ comment: comment }.merge(attributes))
  end

  describe 'SMPTE timecode conversion' do
    it 'converts 29.97 drop-frame reference values' do
      expect(build_target(start_frame: 17_982, fps: 29.97, drop_frame: true).start_timecode).to eq('00:10:00;00')
      expect(build_target(start_frame: 1_500, fps: 29.97, drop_frame: true).start_timecode).to eq('00:00:50;00')
    end

    it 'converts non-drop-frame 25fps values' do
      expect(build_target(start_frame: 1_511, fps: 25, drop_frame: false).start_timecode).to eq('00:01:00:11')
    end

    it 'converts non-drop-frame 30fps values' do
      expect(build_target(start_frame: 0, fps: 30).start_timecode).to eq('00:00:00:00')
      expect(build_target(start_frame: 29, fps: 30).start_timecode).to eq('00:00:00:29')
      expect(build_target(start_frame: 30, fps: 30).start_timecode).to eq('00:00:01:00')
      expect(build_target(start_frame: 1_811, fps: 30).start_timecode).to eq('00:01:00:11')
    end
  end

  describe 'temporal helpers' do
    it 'detects ranges and derives seconds' do
      target = build_target(start_frame: 50, end_frame: 75, fps: 25)

      expect(target).to be_range
      expect(target.start_seconds).to eq(2.0)
      expect(target.end_seconds).to eq(3.0)
    end

    it 'treats matching start and end frames as a point' do
      expect(build_target(start_frame: 50, end_frame: 50, fps: 25)).not_to be_range
    end
  end

  describe 'validations' do
    it 'rejects bbox coordinates outside the normalized 0..1 range' do
      target = build_target(bbox_x: 1.2)

      expect(target).not_to be_valid
      expect(target.errors[:bbox_x]).to be_present
    end

    it 'rejects bounding boxes that extend beyond the right edge' do
      target = build_target(bbox_x: 0.8, bbox_w: 0.3)

      expect(target).not_to be_valid
      expect(target.errors[:bbox_w]).to include('extends beyond the right edge of the media')
    end

    it 'requires an SVG path for path-only shapes' do
      %w[arrow line freehand].each do |shape|
        target = build_target(shape: shape, svg_path: nil)

        expect(target).not_to be_valid
        expect(target.errors[:svg_path]).to include("is required for a '#{shape}' annotation")
      end
    end

    it 'requires fps when a start frame is present' do
      target = build_target(start_frame: 10, fps: nil)

      expect(target).not_to be_valid
      expect(target.errors[:fps]).to include('is required when a frame position is given')
    end

    it 'rejects an end frame before the start frame' do
      target = build_target(start_frame: 20, end_frame: 10, fps: 25)

      expect(target).not_to be_valid
      expect(target.errors[:end_frame]).to include('must not be before start_frame')
    end
  end

  describe 'database constraints' do
    it 'defines normalized bbox and frame-range check constraints' do
      names = ActiveRecord::Base.connection.check_constraints(:annotation_targets).map(&:name)

      expect(names).to include('chk_annotation_targets_bbox_normalised')
      expect(names).to include('chk_annotation_targets_frame_range')
    end
  end

  describe 'style defaults' do
    it 'applies default style' do
      target = build_target
      target.valid?

      expect(target.style).to include(described_class::DEFAULT_STYLE)
    end

    it 'merges caller-supplied style keys over defaults' do
      target = build_target(style: { 'stroke_color' => '#000000', 'opacity' => 0.5 })
      target.valid?

      expect(target.style).to include('stroke_width' => 0.004, 'fill' => 'none')
      expect(target.style).to include('stroke_color' => '#000000', 'opacity' => 0.5)
    end
  end

  describe '.overlapping' do
    it 'returns only annotations intersecting the normalized rectangle' do
      overlapping = described_class.create!(comment: comment, shape: 'rect', bbox_x: 0.2, bbox_y: 0.2, bbox_w: 0.2, bbox_h: 0.2)
      described_class.create!(comment: comment, shape: 'rect', bbox_x: 0.7, bbox_y: 0.7, bbox_w: 0.1, bbox_h: 0.1)

      expect(described_class.overlapping(0.3, 0.3, 0.2, 0.2)).to contain_exactly(overlapping)
    end
  end

  # A "time" target is a position on the timeline with no spatial extent —
  # "the music is too loud here". Without it, commenting on a moment would
  # force the reviewer to draw a meaningless shape somewhere on the frame.
  describe 'time-only targets' do
    it 'is valid with a frame and no spatial extent' do
      target = build_target(
        media_type: 'video', shape: 'time',
        bbox_x: 0, bbox_y: 0, bbox_w: 0, bbox_h: 0,
        start_frame: 300, fps: 25
      )

      expect(target).to be_valid
    end

    it 'requires a frame, since nothing else locates it' do
      target = build_target(
        media_type: 'video', shape: 'time',
        bbox_x: 0, bbox_y: 0, bbox_w: 0, bbox_h: 0
      )

      expect(target).not_to be_valid
      expect(target.errors[:start_frame]).to include("is required for a 'time' annotation")
    end

    it 'still requires a frame rate to interpret the frame' do
      target = build_target(
        media_type: 'video', shape: 'time',
        bbox_x: 0, bbox_y: 0, bbox_w: 0, bbox_h: 0,
        start_frame: 300
      )

      expect(target).not_to be_valid
      expect(target.errors[:fps]).to include('is required when a frame position is given')
    end

    it 'accepts a range' do
      target = build_target(
        media_type: 'video', shape: 'time',
        bbox_x: 0, bbox_y: 0, bbox_w: 0, bbox_h: 0,
        start_frame: 300, end_frame: 500, fps: 25
      )

      expect(target).to be_valid
      expect(target.range?).to be(true)
    end

    it 'is excluded from the spatial scope alongside pins' do
      described_class.create!(
        comment: comment, media_type: 'video', shape: 'time',
        bbox_x: 0, bbox_y: 0, bbox_w: 0, bbox_h: 0, start_frame: 10, fps: 25
      )
      described_class.create!(comment: comment, shape: 'pin', bbox_x: 0.1, bbox_y: 0.1, bbox_w: 0, bbox_h: 0)
      rect = described_class.create!(comment: comment, shape: 'rect', bbox_x: 0.1, bbox_y: 0.1, bbox_w: 0.2, bbox_h: 0.2)

      expect(described_class.spatial).to contain_exactly(rect)
    end

    it 'appears in the temporal scope' do
      time_target = described_class.create!(
        comment: comment, media_type: 'video', shape: 'time',
        bbox_x: 0, bbox_y: 0, bbox_w: 0, bbox_h: 0, start_frame: 10, fps: 25
      )
      described_class.create!(comment: comment, shape: 'rect', bbox_x: 0.1, bbox_y: 0.1, bbox_w: 0.2, bbox_h: 0.2)

      expect(described_class.temporal).to contain_exactly(time_target)
    end
  end
end
