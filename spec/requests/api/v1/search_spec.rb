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
