# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Annotations::ContactSheetPdf do
  let(:author) { create(:user) }
  let(:folder) { create(:folder, user: author) }
  let(:asset) { create(:asset, user: author, folder: folder, title: 'hero-shot.jpg') }
  let!(:version) { create(:asset_version, asset: asset, version_number: 1) }

  def build_thread(body: 'The logo is clipped', status: 'open', shape: 'rect', **geometry)
    thread = asset.comment_threads.create!(
      created_by: author, origin_version: version, status: status, visibility: 'internal'
    )
    comment = thread.comments.create!(body: body, author: author, asset_version: version)
    comment.annotation_targets.create!({
      media_type: 'image', shape: shape,
      bbox_x: 0.1, bbox_y: 0.2, bbox_w: 0.3, bbox_h: 0.4,
      source_width: 4000, source_height: 3000
    }.merge(geometry))
    thread
  end

  def render_for(threads)
    described_class.new(asset: asset, threads: threads).render
  end

  it 'renders a valid PDF' do
    pdf = render_for([ build_thread ])

    expect(pdf[0, 4]).to eq('%PDF')
    expect(pdf.bytesize).to be > 1_000
  end

  it 'renders a sheet even when there is nothing to review' do
    pdf = render_for(asset.comment_threads.none)

    # An empty review record is still a record; refusing to produce one would
    # make "export the sign-off sheet" fail unpredictably.
    expect(pdf[0, 4]).to eq('%PDF')
  end

  it 'degrades to a text-only sheet rather than failing when the preview is unreadable' do
    allow(StorageManager).to receive(:read_file_from_adapter).and_raise(Errno::ECONNREFUSED)

    pdf = render_for([ build_thread ])

    # Nothing in the sheet may fail the export: a review record without its
    # plate is still useful, a 500 is not.
    expect(pdf[0, 4]).to eq('%PDF')
  end

  it 'renders comment text outside the Windows-1252 range' do
    # Prawn's built-in fonts raise on anything outside Windows-1252, so a
    # single emoji would abort the whole export if Roboto were not registered.
    pdf = render_for([ build_thread(body: 'Needs more contrast — 対比 🚀') ])

    expect(pdf[0, 4]).to eq('%PDF')
  end

  it 'renders every supported shape without raising' do
    threads = %w[rect ellipse pin highlight].map { |shape| build_thread(shape: shape) }
    # arrow, line and freehand are path-based and the model requires geometry.
    threads += %w[arrow line freehand].map do |shape|
      build_thread(shape: shape, svg_path: 'M 0.1,0.1 L 0.4,0.3 L 0.2,0.6')
    end

    expect { render_for(threads) }.not_to raise_error
  end

  it 'renders a video review with timecode rather than failing on frame data' do
    thread = asset.comment_threads.create!(created_by: author, origin_version: version, visibility: 'internal')
    comment = thread.comments.create!(body: 'Cut is late', author: author, asset_version: version)
    comment.annotation_targets.create!(
      media_type: 'video', shape: 'time',
      start_frame: 1500, end_frame: 1620, fps: 29.97, drop_frame: true
    )

    expect(render_for([ thread ])[0, 4]).to eq('%PDF')
  end
end
