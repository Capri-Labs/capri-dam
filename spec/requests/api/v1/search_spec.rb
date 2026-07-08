# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Search', type: :request do
  let(:user) { create(:user) }

  def json
    response.parsed_body
  end

  def create_search_asset(title:, status: :ready, content_type:, file_size:, width: nil, height: nil,
                          updated_at: Time.current, extra_properties: {})
    asset = create(
      :asset,
      user: user,
      title: title,
      status: status,
      properties: {
        'content_type' => content_type,
        'original_filename' => "#{title.parameterize}.bin",
        'file_size' => file_size.to_s,
        'size_human' => "#{file_size} B",
        'width' => width&.to_s,
        'height' => height&.to_s,
      }.compact.merge(extra_properties)
    )
    asset.update_column(:updated_at, updated_at)
    asset
  end

  describe 'GET /api/v1/search' do
    context 'when authenticated' do
      before { sign_in user }

      it 'supports basic text search' do
        matching = create_search_asset(title: 'Brand Logo', content_type: 'image/png', file_size: 512_000)
        create_search_asset(title: 'Campaign Video', content_type: 'video/mp4', file_size: 2.megabytes)

        get '/api/v1/search', params: { q: 'Logo' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(matching.uuid)
      end

      it 'filters by mime_group=images' do
        image_asset = create_search_asset(title: 'Photo', content_type: 'image/jpeg', file_size: 400_000)
        create_search_asset(title: 'Spec Sheet', content_type: 'application/pdf', file_size: 800_000)

        get '/api/v1/search', params: { mime_group: 'images' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(image_asset.uuid)
        expect(json['results'].pluck('content_type')).to all(start_with('image/'))
      end

      it 'exposes a generated preview_url for special formats a browser cannot render natively' do
        psd = create_search_asset(
          title: 'Layered Artwork',
          content_type: 'image/vnd.adobe.photoshop',
          file_size: 5.megabytes,
          extra_properties: {
            'storage_path' => 'search_spec/artwork.psd',
            'preview_storage_path' => 'previews/artwork.png',
            'preview_content_type' => 'image/png',
          }
        )

        get '/api/v1/search', params: { q: 'Layered' }, as: :json

        expect(response).to have_http_status(:ok)
        result = json['results'].find { |r| r['uuid'] == psd.uuid }
        expect(result['thumb_url']).to include('variant=preview')
        expect(result['preview_url']).to include('variant=preview')
        expect(result['url']).not_to include('variant=preview')
        expect(result['web_renderable']).to be(false)
      end

      it 'marks natively web-renderable images as such and points thumb_url at the original file' do
        jpeg = create_search_asset(
          title: 'Plain Photo',
          content_type: 'image/jpeg',
          file_size: 400_000,
          extra_properties: { 'storage_path' => 'search_spec/photo.jpg' }
        )

        get '/api/v1/search', params: { q: 'Plain Photo' }, as: :json

        result = json['results'].find { |r| r['uuid'] == jpeg.uuid }
        expect(result['web_renderable']).to be(true)
        expect(result['thumb_url']).not_to include('variant=preview')
      end

      it 'filters by modified_within=week' do
        recent_asset = create_search_asset(
          title: 'Recent Asset',
          content_type: 'image/png',
          file_size: 300_000,
          updated_at: 2.days.ago
        )
        create_search_asset(
          title: 'Old Asset',
          content_type: 'image/png',
          file_size: 300_000,
          updated_at: 2.weeks.ago
        )

        get '/api/v1/search', params: { modified_within: 'week' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(recent_asset.uuid)
      end

      it 'filters by modified_within=day, month, and year' do
        day_asset = create_search_asset(
          title: 'Day Asset',
          content_type: 'image/png',
          file_size: 300_000,
          updated_at: 12.hours.ago
        )
        month_asset = create_search_asset(
          title: 'Month Asset',
          content_type: 'image/png',
          file_size: 300_000,
          updated_at: 20.days.ago
        )
        year_asset = create_search_asset(
          title: 'Year Asset',
          content_type: 'image/png',
          file_size: 300_000,
          updated_at: 11.months.ago
        )
        create_search_asset(
          title: 'Ancient Asset',
          content_type: 'image/png',
          file_size: 300_000,
          updated_at: 2.years.ago
        )

        get '/api/v1/search', params: { modified_within: 'day' }, as: :json
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(day_asset.uuid)

        get '/api/v1/search', params: { modified_within: 'month' }, as: :json
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(day_asset.uuid, month_asset.uuid)

        get '/api/v1/search', params: { modified_within: 'year' }, as: :json
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(
          day_asset.uuid,
          month_asset.uuid,
          year_asset.uuid
        )
      end

      it 'filters by file_size_group=small' do
        small_asset = create_search_asset(title: 'Tiny Icon', content_type: 'image/png', file_size: 250.kilobytes)
        create_search_asset(title: 'Large Brochure', content_type: 'application/pdf', file_size: 2.megabytes)

        get '/api/v1/search', params: { file_size_group: 'small' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(small_asset.uuid)
      end

      it 'filters published assets via publish_status=published' do
        published_asset = create_search_asset(title: 'Published Asset', status: :ready, content_type: 'image/png', file_size: 600_000)
        create_search_asset(title: 'Draft Asset', status: :draft, content_type: 'image/png', file_size: 600_000)

        get '/api/v1/search', params: { publish_status: 'published' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(published_asset.uuid)
        expect(json['results'].pluck('status')).to contain_exactly('active')
      end

      it 'filters approved assets via approved_status=approved' do
        approved_asset = create_search_asset(title: 'Approved Asset', status: :approved, content_type: 'image/png', file_size: 600_000)
        create_search_asset(title: 'Rejected Asset', status: :rejected, content_type: 'image/png', file_size: 600_000)

        get '/api/v1/search', params: { approved_status: 'approved' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(approved_asset.uuid)
        expect(json['results'].pluck('status')).to contain_exactly('approved')
      end

      it 'filters by orientation=horizontal' do
        horizontal_asset = create_search_asset(
          title: 'Landscape',
          content_type: 'image/jpeg',
          file_size: 700_000,
          width: 1920,
          height: 1080
        )
        create_search_asset(
          title: 'Portrait',
          content_type: 'image/jpeg',
          file_size: 700_000,
          width: 800,
          height: 1200
        )

        get '/api/v1/search', params: { orientation: 'horizontal' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(horizontal_asset.uuid)
      end

      it 'returns pagination metadata' do
        11.times do |index|
          create_search_asset(
            title: "Asset #{index}",
            content_type: 'image/png',
            file_size: 100_000 + index,
            updated_at: index.minutes.ago
          )
        end

        get '/api/v1/search', params: { page: 1, per_page: 10 }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['meta']).to include(
          'page' => 1,
          'per_page' => 10,
          'total_found' => 11,
          'total_pages' => 2
        )
        expect(json['results'].length).to eq(10)
      end

      it 'defaults per_page to 25 when the param is omitted' do
        create_search_asset(title: 'Default Page Size', content_type: 'image/png', file_size: 100_000)

        get '/api/v1/search', as: :json

        expect(response).to have_http_status(:ok)
        expect(json['meta']).to include('per_page' => 25)
      end

      it 'formats size as a human-readable string derived from the raw byte count' do
        asset = create_search_asset(title: 'Sized Asset', content_type: 'image/png', file_size: 512_000)

        get '/api/v1/search', params: { q: 'Sized Asset' }, as: :json

        result = json['results'].find { |r| r['uuid'] == asset.uuid }
        expect(result['size']).to eq(ActiveSupport::NumberHelper.number_to_human_size(512_000))
        expect(result['file_size']).to eq(512_000)
      end

      it 'excludes trashed (soft-deleted) assets by default' do
        active_asset = create_search_asset(title: 'Bin Toggle Active', content_type: 'image/png', file_size: 100_000)
        trashed_asset = create_search_asset(title: 'Bin Toggle Trashed', content_type: 'image/png', file_size: 100_000)
        trashed_asset.update_column(:deleted_at, Time.current)

        get '/api/v1/search', params: { q: 'Bin Toggle' }, as: :json

        uuids = json['results'].map { |r| r['uuid'] }
        expect(uuids).to include(active_asset.uuid)
        expect(uuids).not_to include(trashed_asset.uuid)
        expect(json['meta']['include_bin']).to eq(false)
      end

      it 'includes trashed (soft-deleted) assets, flagged via in_bin, when include_bin=true' do
        active_asset = create_search_asset(title: 'Bin Flag Active', content_type: 'image/png', file_size: 100_000)
        trashed_asset = create_search_asset(title: 'Bin Flag Trashed', content_type: 'image/png', file_size: 100_000)
        trashed_asset.update_column(:deleted_at, Time.current)

        get '/api/v1/search', params: { q: 'Bin Flag', include_bin: 'true' }, as: :json

        results_by_uuid = json['results'].index_by { |r| r['uuid'] }
        expect(results_by_uuid.keys).to contain_exactly(active_asset.uuid, trashed_asset.uuid)
        expect(results_by_uuid[active_asset.uuid]['in_bin']).to eq(false)
        expect(results_by_uuid[trashed_asset.uuid]['in_bin']).to eq(true)
        expect(json['meta']['include_bin']).to eq(true)
      end

      it 'filters by mode=videos' do
        video_asset = create_search_asset(title: 'Demo Reel', content_type: 'video/mp4', file_size: 1.megabyte)
        create_search_asset(title: 'Still', content_type: 'image/png', file_size: 1.megabyte)

        get '/api/v1/search', params: { mode: 'videos' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(video_asset.uuid)
      end

      it 'ignores unknown mime groups' do
        image_asset = create_search_asset(title: 'Poster', content_type: 'image/png', file_size: 1.megabyte)
        doc_asset = create_search_asset(title: 'Brief', content_type: 'application/pdf', file_size: 1.megabyte)

        get '/api/v1/search', params: { mime_group: 'bogus' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['results'].map { |result| result['uuid'] }).to contain_exactly(image_asset.uuid, doc_asset.uuid)
      end

      it 'returns facets including metadata_fields key' do
        get '/api/v1/search', as: :json

        expect(response).to have_http_status(:ok)
        expect(json['meta']['facets']).to have_key('metadata_fields')
        expect(json['meta']['facets']['metadata_fields']).to be_a(Hash)
      end

      it 'filters by dynamic metadata property key' do
        isolated_user = create(:user)
        asset_with_brand = create(:asset, user: isolated_user,
          properties: { 'content_type' => 'image/png', 'dam:brand' => 'Acme' })
        asset_other_brand = create(:asset, user: isolated_user,
          properties: { 'content_type' => 'image/png', 'dam:brand' => 'Other' })

        # Use explicit query string (not `as: :json`) so request.query_parameters sees the key
        get '/api/v1/search?dam%3Abrand=Acme',
          headers: { 'Accept' => 'application/json', 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:ok)
        uuids = json['results'].map { |r| r['uuid'] }
        expect(uuids).to include(asset_with_brand.uuid)
        expect(uuids).not_to include(asset_other_brand.uuid)
      end

      it 'ignores dynamic filter params with unsafe key characters' do
        get '/api/v1/search', params: { 'bad; DROP TABLE assets;--' => 'x' }, as: :json

        expect(response).to have_http_status(:ok)
      end

      it 'filters by nested JSONB path using dot notation' do
        asset_vivid = create(:asset, user: user,
          properties: { 'content_type' => 'image/png',
                        'editor_state' => { 'filter' => 'Vivid', 'crop_aspect' => 'free' } })
        asset_none  = create(:asset, user: user,
          properties: { 'content_type' => 'image/png',
                        'editor_state' => { 'filter' => 'None', 'crop_aspect' => 'free' } })

        get '/api/v1/search?editor_state.filter=Vivid',
          headers: { 'Accept' => 'application/json' }

        expect(response).to have_http_status(:ok)
        uuids = json['results'].map { |r| r['uuid'] }
        expect(uuids).to include(asset_vivid.uuid)
        expect(uuids).not_to include(asset_none.uuid)
      end
    end

    it 'returns 401 without authentication' do
      get '/api/v1/search', params: { q: 'logo' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# ---- merged from search_coverage_spec.rb ----
RSpec.describe "Api::V1::Search coverage", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  def json = response.parsed_body

  def search_asset(title, props = {}, status: :ready, updated_at: Time.current)
    asset = create(:asset, user: user, title: title, status: status, properties: {
      "content_type" => "image/png", "file_size" => "1024", "size_human" => "1 KB"
    }.merge(props))
    asset.update_column(:updated_at, updated_at)
    asset
  end

  it "filters by mode variants, schema and other mime group" do
    image = search_asset("Image", { "content_type" => "image/png", "applied_schema_id" => "10" })
    file = search_asset("Binary", { "content_type" => "application/octet-stream" })
    search_asset("Video", { "content_type" => "video/mp4" })
    search_asset("Doc", { "content_type" => "application/pdf" })

    get "/api/v1/search", params: { mode: "images", schema_id: 10 }, as: :json
    expect(json["results"].map { |r| r["uuid"] }).to contain_exactly(image.uuid)

    get "/api/v1/search", params: { mode: "files" }, as: :json
    expect(json["results"].map { |r| r["uuid"] }).to include(file.uuid)

    get "/api/v1/search", params: { mime_group: "other" }, as: :json
    expect(json["results"].map { |r| r["uuid"] }).to include(file.uuid)
  end

  it "filters file sizes, publication states, orientations, style, video and audio metadata" do
    match = search_asset("Match", {
      "content_type" => "video/mpeg4", "file_size" => 12.megabytes.to_s,
      "width" => "100", "height" => "100", "color_mode" => "grayscale",
      "video_height" => "1080", "video_width" => "1920", "video_format" => "mpeg4",
      "video_codec" => "h264", "video_bitrate" => "6000", "audio_codec" => "aac", "audio_bitrate" => "320"
    }, status: :rejected)
    search_asset("Nope", { "content_type" => "image/png", "file_size" => 2.megabytes.to_s }, status: :ready)

    get "/api/v1/search", params: {
      file_size_group: "large", approved_status: "rejected", orientation: "square", style: "black_white",
      video_height_min: 720, video_height_max: 1200, video_width_min: 1000, video_width_max: 2000,
      video_format: "mpeg4", video_codec: "h264", video_bitrate_min: 1000, video_bitrate_max: 8000,
      audio_codec: "aac", audio_bitrate_min: 128, audio_bitrate_max: 512, sort_by: "size", sort_dir: "asc"
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["results"].map { |r| r["uuid"] }).to contain_exactly(match.uuid)
  end

  it "clamps pagination and sorts by name/modified/created" do
    search_asset("B", updated_at: 2.days.ago)
    search_asset("A", updated_at: 1.day.ago)

    get "/api/v1/search", params: { page: -2, per_page: 500, sort_by: "name", sort_dir: "asc" }, as: :json
    expect(json["meta"]).to include("page" => 1, "per_page" => 100)
    expect(json["results"].map { |r| r["title"] }.first(2)).to eq(%w[A B])

    get "/api/v1/search", params: { sort_by: "modified" }, as: :json
    expect(response).to have_http_status(:ok)

    get "/api/v1/search", params: { sort_by: "created", sort_dir: "asc" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "builds schema-driven and discovered metadata facets" do
    create(:metadata_schema, tabs: [ { "fields" => [
      { "field_type" => "select", "map_to_property" => "dam:brand", "label" => "Brand" },
      { "field_type" => "textarea", "map_to_property" => "hidden", "label" => "Hidden" },
    ] } ])
    search_asset("One", { "dam:brand" => "Capri", "market" => "EU", "editor_state" => { "filter" => "Vivid" } })
    search_asset("Two", { "dam:brand" => "Acme", "market" => "US", "editor_state" => { "filter" => "None" } })

    get "/api/v1/search", as: :json
    facets = json["meta"]["facets"]["metadata_fields"]
    expect(facets["dam:brand"]["label"]).to eq("Brand")
    expect(facets).to have_key("market")
    expect(facets).to have_key("editor_state.filter")
  end

  it "requires authentication" do
    sign_out user

    get "/api/v1/search", as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "filters by text, recency, mime groups, publish status, orientation, style, and dynamic metadata" do
    match = search_asset("Needle", {
      "original_filename" => "campaign.pdf",
      "content_type" => "application/pdf",
      "file_size" => 5.megabytes.to_s,
      "width" => "1600",
      "height" => "900",
      "color_mode" => "rgb",
      "dc:creator" => "Maya",
      "editor_state" => { "filter" => "Reviewed" },
    }, status: :approved, updated_at: 30.minutes.ago)
    search_asset("Old", {
      "original_filename" => "campaign.pdf",
      "content_type" => "application/zip",
      "file_size" => 512.kilobytes.to_s,
      "width" => "900",
      "height" => "1600",
      "color_mode" => "grayscale",
      "dc:creator" => "Maya",
      "editor_state" => { "filter" => "Draft" },
    }, status: :draft, updated_at: 2.days.ago)

    get "/api/v1/search", params: {
      q: "campaign",
      mode: "documents",
      mime_group: "documents",
      modified_within: "hour",
      file_size_group: "medium",
      publish_status: "published",
      approved_status: "approved",
      orientation: "horizontal",
      style: "color",
      "dc:creator" => "Maya",
      "editor_state.filter" => "Reviewed",
      ".ignored" => "Reviewed",
      "bad key!" => "Maya",
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["results"].map { |result| result["uuid"] }).to contain_exactly(match.uuid)
    expect(json["meta"]["facets"]["mime_group"]).to include("documents" => 1)
  end

  it "handles archives, multimedia, small files, unpublished status, vertical orientation, and empty facets" do
    archive = search_asset("Archive", {
      "content_type" => "application/zip",
      "file_size" => 100.kilobytes.to_s,
      "width" => "600",
      "height" => "900",
    }, status: :draft)
    search_asset("Audio", { "content_type" => "audio/aac", "file_size" => 20.megabytes.to_s }, status: :ready)

    get "/api/v1/search", params: {
      mime_group: "archives",
      file_size_group: "small",
      publish_status: "unpublished",
      orientation: "vertical",
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["results"].map { |result| result["uuid"] }).to contain_exactly(archive.uuid)

    get "/api/v1/search", params: { mime_group: "multimedia" }, as: :json
    expect(json["meta"]["facets"]["mime_group"]).to include("multimedia" => 1)

    Asset.delete_all
    get "/api/v1/search", as: :json
    expect(json["results"]).to be_empty
    expect(json["meta"]["facets"]["metadata_fields"]).to eq({})
  end

  it "preserves raw enum names when normalizing statuses" do
    asset = search_asset("Approved", { "content_type" => "image/png" }, status: :approved)
    allow_any_instance_of(Asset).to receive(:read_attribute_before_type_cast).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      args.first == :status ? "approved" : original.call(*args)
    end

    get "/api/v1/search", params: { q: asset.title }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["results"]).to contain_exactly(hash_including("uuid" => asset.uuid, "status" => "approved"))
  end

  it "ignores invalid dynamic filters and blank filter values from the raw query string" do
    keep = search_asset("Keep", { "dc:creator" => "Maya" })
    skip = search_asset("Skip", { "dc:creator" => "Other" })

    get "/api/v1/search?dc%3Acreator=%20,%20&bad%20key=x&editor_state.=Reviewed&title..value=bad",
      headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(json["results"].map { |result| result["uuid"] }).to contain_exactly(keep.uuid, skip.uuid)
  end

  it "splits scalar and nested metadata facet values while skipping unusable schema and discovered keys" do
    create(:metadata_schema, tabs: [ { "fields" => [
      { "field_type" => "select", "map_to_property" => nil, "label" => "Missing Map" },
      { "field_type" => "select", "map_to_property" => "bad key!", "label" => "Bad Key" },
      { "field_type" => "select", "map_to_property" => "unused_field", "label" => "Unused Field" },
    ] } ])

    search_asset("Facet One", {
      "dc:creator" => "Maya, Lee",
      "editor_state" => { "filter" => "Reviewed, Approved", "geometry" => { "x" => 10 } },
      "empty_state" => { "filter" => " " },
    })
    search_asset("Facet Two", {
      "dc:creator" => "Maya",
      "editor_state" => { "filter" => "Reviewed" },
    })

    get "/api/v1/search", as: :json

    facets = json.dig("meta", "facets", "metadata_fields")
    expect(facets.dig("dc:creator", "label")).to eq("Creator")
    expect(facets.dig("dc:creator", "values")).to include(
      { "value" => "Maya", "count" => 2 },
      { "value" => "Lee", "count" => 1 }
    )
    expect(facets.dig("editor_state.filter", "values")).to include(
      { "value" => "Reviewed", "count" => 2 },
      { "value" => "Approved", "count" => 1 }
    )
    expect(facets).not_to have_key("unused_field")
    expect(facets).not_to have_key("editor_state.geometry")
    expect(facets).not_to have_key("empty_state.filter")
  end

  it "returns nil timestamps when an asset lacks created_at and updated_at values" do
    asset = search_asset("Untimed")
    allow_any_instance_of(Asset).to receive(:created_at).and_return(nil) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Asset).to receive(:updated_at).and_return(nil) # rubocop:disable RSpec/AnyInstance

    get "/api/v1/search", params: { q: asset.title }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["results"]).to contain_exactly(hash_including("uuid" => asset.uuid, "created_at" => nil, "updated_at" => nil))
  end
end

RSpec.describe "Api::V1::Search — folders, semantic modes, suggestions, and caching", type: :request do
  let(:user) { create(:user) }
  let(:gateway_url) { "http://localhost:8000" }

  def json
    response.parsed_body
  end

  before { sign_in user }

  describe "GET /api/v1/search?mode=folders" do
    it "searches Folder records by name instead of Asset records" do
      matching = create(:folder, name: "Marketing Assets", user: user)
      create(:folder, name: "Legal Archive", user: user)

      get "/api/v1/search", params: { mode: "folders", q: "Marketing" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("meta", "result_type")).to eq("folder")
      expect(json["results"]).to contain_exactly(
        hash_including("id" => matching.id, "title" => "Marketing Assets", "type" => "folder",
                        "href" => "/folders?folder=#{matching.id}")
      )
    end

    it "excludes soft-deleted folders" do
      create(:folder, :trashed, name: "Old Campaign", user: user)

      get "/api/v1/search", params: { mode: "folders", q: "Old" }, as: :json

      expect(json["results"]).to be_empty
    end
  end

  describe "GET /api/v1/search?mode=visual|agentic (semantic pipeline)" do
    %w[visual agentic].each do |mode|
      it "embeds the query and returns pgvector nearest-neighbour results for mode=#{mode}" do
        asset = create(:asset, user: user, title: "Hero Shot", properties: { "content_type" => "image/jpeg" })

        stub_request(:post, "#{gateway_url}/api/embed_query")
          .with(body: { text: "sunset over mountains" }.to_json)
          .to_return(status: 200, body: { vector: Array.new(1536, 0.02) }.to_json,
                     headers: { "Content-Type" => "application/json" })

        relation = Asset.where(id: asset.id).select("assets.*, 0.2 AS neighbor_distance")
        allow(Asset).to receive(:nearest_to_vector).and_return(relation)

        get "/api/v1/search", params: { mode: mode, q: "sunset over mountains" }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json.dig("meta", "result_type")).to eq("semantic")
        expect(json["results"].first).to include("uuid" => asset.uuid, "similarity_score" => "0.8")
      end
    end

    it "falls back to lexical search when the AI Gateway is unreachable" do
      matching = create(:asset, user: user, title: "Sunset Beach", properties: { "content_type" => "image/jpeg" })

      stub_request(:post, "#{gateway_url}/api/embed_query").to_timeout

      get "/api/v1/search", params: { mode: "visual", q: "Sunset" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("meta", "semantic_fallback")).to be true
      expect(json["results"].map { |r| r["uuid"] }).to include(matching.uuid)
    end
  end

  describe "GET /api/v1/search/suggestions" do
    it "returns an empty result set for a blank query" do
      get "/api/v1/search/suggestions", params: { q: "  " }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["results"]).to eq([])
    end

    it "returns a mixed list of matching assets and folders" do
      asset = create(:asset, user: user, title: "Brand Kit", properties: { "content_type" => "image/png" })
      folder = create(:folder, name: "Brand Guidelines", user: user)
      allow_any_instance_of(Api::V1::SearchController).to receive(:asset_url_for).and_return("/api/v1/assets/local/#{asset.uuid}") # rubocop:disable RSpec/AnyInstance

      get "/api/v1/search/suggestions", params: { q: "Brand" }, as: :json

      expect(response).to have_http_status(:ok)
      types = json["results"].map { |r| r["type"] }
      expect(types).to contain_exactly("asset", "folder")
      expect(json["results"]).to include(
        hash_including("type" => "asset", "title" => "Brand Kit", "href" => "/assets?id=#{asset.uuid}"),
        hash_including("type" => "folder", "title" => "Brand Guidelines", "href" => "/folders?folder=#{folder.id}")
      )
    end

    it "matches a fragment anywhere within the filename, not just as a prefix" do
      asset = create(:asset, user: user, title: "Brand_Guidelines_dup1.jpg",
                      properties: { "content_type" => "image/jpeg", "original_filename" => "Brand_Guidelines_dup1.jpg" })
      allow_any_instance_of(Api::V1::SearchController).to receive(:asset_url_for).and_return("/api/v1/assets/local/#{asset.uuid}") # rubocop:disable RSpec/AnyInstance

      get "/api/v1/search/suggestions", params: { q: "dup1" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["results"]).to include(hash_including("type" => "asset", "id" => asset.uuid))
    end

    it "matches fragments found only within embedded metadata (keywords/description)" do
      asset = create(:asset, user: user, title: "Untitled",
                      properties: { "content_type" => "image/jpeg", "keywords" => "sunset, mountains, dusk" })
      allow_any_instance_of(Api::V1::SearchController).to receive(:asset_url_for).and_return("/api/v1/assets/local/#{asset.uuid}") # rubocop:disable RSpec/AnyInstance

      get "/api/v1/search/suggestions", params: { q: "mountains" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["results"]).to include(hash_including("type" => "asset", "id" => asset.uuid))
    end
  end

  describe "Redis-backed response caching" do
    it "serves the second identical request from SearchCache without re-querying" do
      create(:asset, user: user, title: "Cached Hit", properties: { "content_type" => "image/png" })
      allow(Rails.env).to receive(:test?).and_return(false)
      fake_store = {}
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:get) { |key| fake_store[key] }
      allow(fake_redis).to receive(:setex) { |key, _ttl, value| fake_store[key] = value }
      allow(SearchCache).to receive(:redis).and_return(fake_redis)

      get "/api/v1/search", params: { q: "Cached Hit" }, as: :json
      expect(json["results"].size).to eq(1)

      # Mutate the DB after the first (now cached) request — a second identical
      # request should still return the stale cached payload, proving caching works.
      Asset.update_all(deleted_at: Time.current)

      get "/api/v1/search", params: { q: "Cached Hit" }, as: :json
      expect(json["results"].size).to eq(1)
      expect(fake_store.keys.first).to start_with("dam:search:index:")
    end

    it "falls back to an uncached response when Redis is unreachable" do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(SearchCache.redis).to receive(:get).and_raise(Redis::CannotConnectError)

      create(:asset, user: user, title: "Resilient Asset", properties: { "content_type" => "image/png" })

      get "/api/v1/search", params: { q: "Resilient" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["results"].map { |r| r["title"] }).to include("Resilient Asset")
    end
  end
end
