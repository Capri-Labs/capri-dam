# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Video Profiles API', type: :request do
  # ── Shared setup ─────────────────────────────────────────────────────────────
  let(:admin_user)   { create(:user, admin: true) }
  let(:regular_user) { create(:user, admin: false) }
  let(:profile)      { create(:video_profile) }

  # ── Schema helpers ────────────────────────────────────────────────────────────
  PRESET_SCHEMA = {
    type: :object,
    properties: {
      id:                  { type: :integer },
      name:                { type: :string },
      video_format_codec:  { type: :string, enum: %w[h264] },
      width:               { type: :integer, nullable: true, description: 'null = auto' },
      height:              { type: :integer },
      keep_aspect_ratio:   { type: :boolean },
      video_bitrate_kbps:  { type: :integer },
      frame_rate_fps:      { type: :integer },
      audio_codec:         { type: :string, enum: %w[he_aac aac mp3] },
      audio_bitrate_kbps:  { type: :integer },
      two_pass_encoding:   { type: :boolean },
      constant_bitrate:    { type: :boolean },
      h264_profile:        { type: :string, nullable: true, enum: %w[baseline main high] },
      audio_sampling_rate: { type: :integer, nullable: true },
      advanced_params: {
        type: :object,
        description: 'Custom encoding params: h264Level, keyframe, minBitrate, maxBitrate, audioBitrateCustom',
        properties: {
          h264Level:          { type: :string, description: '10 * h264 level, e.g. "30" for 3.0' },
          keyframe:           { type: :string, description: 'Target keyframe interval in frames (recommended: 60–300)' },
          minBitrate:         { type: :string, description: 'Min bitrate in Kbps for VBR encodings' },
          maxBitrate:         { type: :string, description: 'Max bitrate in Kbps (recommended: 2x encoding bitrate)' },
          audioBitrateCustom: { type: :string, description: '"true"/"false" — force constant audio bitrate' },
        },
      },
      position:   { type: :integer },
      size_label: { type: :string },
      created_at: { type: :string, format: 'date-time' },
      updated_at: { type: :string, format: 'date-time' },
    },
  }.freeze

  PROFILE_SCHEMA = {
    type: :object,
    properties: {
      id:                            { type: :integer },
      name:                          { type: :string },
      description:                   { type: :string, nullable: true },
      encode_for_adaptive_streaming: { type: :boolean },
      smart_crop_ratios: {
        type: :array,
        items: {
          type: :object,
          properties: {
            name:       { type: :string, example: '16:9' },
            crop_ratio: { type: :string, example: '16:9' },
          },
        },
      },
      adaptive_streaming_warnings: { type: :array, items: { type: :string } },
      folder_count:                { type: :integer },
      created_at:                  { type: :string, format: 'date-time' },
      updated_at:                  { type: :string, format: 'date-time' },
    },
  }.freeze

  # ── GET /api/v1/video_profiles ───────────────────────────────────────────────
  path '/api/v1/video_profiles' do
    get 'Lists all active Video Profiles' do
      tags     'Tools - Video Profiles'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'profiles retrieved' do
        schema type: :array, items: PROFILE_SCHEMA
        run_test!
      end
    end

    post 'Creates a new Video Profile' do
      tags     'Tools - Video Profiles'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ :video_profile ],
        properties: {
          video_profile: {
            type: :object,
            required: [ :name ],
            properties: {
              name:                          { type: :string, example: 'Adaptive HD' },
              description:                   { type: :string, example: 'Adaptive HLS for desktop and mobile' },
              encode_for_adaptive_streaming: { type: :boolean, example: true },
              smart_crop_ratios: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    name:       { type: :string, example: '16:9' },
                    crop_ratio: { type: :string, example: '16:9' },
                  },
                },
              },
              encoding_presets_attributes: {
                type: :array,
                items: {
                  type: :object,
                  required: [ :name, :height, :video_bitrate_kbps ],
                  properties: {
                    name:               { type: :string, example: '720p' },
                    video_format_codec: { type: :string, example: 'h264' },
                    width:              { type: :integer, nullable: true, example: nil },
                    height:             { type: :integer, example: 720 },
                    keep_aspect_ratio:  { type: :boolean, example: true },
                    video_bitrate_kbps: { type: :integer, example: 3000 },
                    frame_rate_fps:     { type: :integer, example: 30 },
                    audio_codec:        { type: :string, example: 'he_aac' },
                    audio_bitrate_kbps: { type: :integer, example: 128 },
                    position:           { type: :integer, example: 0 },
                  },
                },
              },
            },
          },
        },
      }

      response '201', 'profile created' do
        schema PROFILE_SCHEMA.merge(
          properties: PROFILE_SCHEMA[:properties].merge(
            encoding_presets: { type: :array, items: PRESET_SCHEMA }
          )
        )
        run_test!
      end

      response '403', 'forbidden – admin only' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'validation failed' do
        schema type: :object, properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  # ── GET /api/v1/video_profiles/:id ──────────────────────────────────────────
  path '/api/v1/video_profiles/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true

    get 'Retrieves a single Video Profile with its encoding presets' do
      tags     'Tools - Video Profiles'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'profile found' do
        schema PROFILE_SCHEMA.merge(
          properties: PROFILE_SCHEMA[:properties].merge(
            encoding_presets: { type: :array, items: PRESET_SCHEMA },
            folders:          { type: :array, items: { type: :object } }
          )
        )
        run_test!
      end

      response '404', 'not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    patch 'Updates a Video Profile' do
      tags     'Tools - Video Profiles'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          video_profile: {
            type: :object,
            properties: {
              name:                          { type: :string },
              description:                   { type: :string },
              encode_for_adaptive_streaming: { type: :boolean },
            },
          },
        },
      }

      response '200', 'profile updated' do
        schema PROFILE_SCHEMA
        run_test!
      end

      response '403', 'forbidden – admin only' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'validation failed' do
        schema type: :object, properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end

    delete 'Soft-deletes a Video Profile' do
      tags     'Tools - Video Profiles'
      security [ Bearer: [] ]

      response '204', 'deleted (no content)' do
        run_test!
      end

      response '403', 'forbidden – admin only' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ── POST /api/v1/video_profiles/:id/copy ─────────────────────────────────────
  path '/api/v1/video_profiles/{id}/copy' do
    parameter name: :id, in: :path, type: :integer, required: true

    post 'Copies a Video Profile under a new name' do
      tags     'Tools - Video Profiles'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          name: { type: :string, example: 'Adaptive HD (copy)' },
        },
      }

      response '201', 'profile copied' do
        schema PROFILE_SCHEMA.merge(
          properties: PROFILE_SCHEMA[:properties].merge(
            encoding_presets: { type: :array, items: PRESET_SCHEMA }
          )
        )
        run_test!
      end

      response '403', 'forbidden – admin only' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ── POST /api/v1/video_profiles/:id/apply_to_folder ─────────────────────────
  path '/api/v1/video_profiles/{id}/apply_to_folder' do
    parameter name: :id, in: :path, type: :integer, required: true

    post 'Applies a Video Profile to a folder' do
      tags     'Tools - Video Profiles'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ :folder_id ],
        properties: {
          folder_id: { type: :string, format: :uuid, example: '3fa85f64-5717-4562-b3fc-2c963f66afa6' },
        },
      }

      response '201', 'profile applied to folder' do
        schema type: :object,
               properties: {
                 profile_id: { type: :integer },
                 folder_id:  { type: :string },
               }
        run_test!
      end

      response '400', 'missing folder_id' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '403', 'forbidden – admin only' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ── DELETE /api/v1/video_profiles/:id/remove_from_folder ─────────────────────
  path '/api/v1/video_profiles/{id}/remove_from_folder' do
    parameter name: :id, in: :path, type: :integer, required: true

    delete 'Removes a Video Profile from a folder' do
      tags     'Tools - Video Profiles'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ :folder_id ],
        properties: {
          folder_id: { type: :string, format: :uuid },
        },
      }

      response '204', 'removed (no content)' do
        run_test!
      end

      response '400', 'missing folder_id' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ── GET /api/v1/video_profiles/:id/folders ──────────────────────────────────
  path '/api/v1/video_profiles/{id}/folders' do
    parameter name: :id, in: :path, type: :integer, required: true

    get 'Lists folders the Video Profile is applied to' do
      tags     'Tools - Video Profiles'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'folders listed' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id:   { type: :string },
                   name: { type: :string },
                   path: { type: :string },
                 },
               }
        run_test!
      end
    end
  end

  # ── Unit-level request specs ──────────────────────────────────────────────────

  describe 'GET /api/v1/video_profiles', :without_rswag do
    context 'as authenticated user' do
      before { sign_in admin_user }

      it 'returns 200 with active profiles only' do
        create_list(:video_profile, 2)
        create(:video_profile, :deleted)

        get '/api/v1/video_profiles', as: :json
        expect(response).to have_http_status(:ok)

        body = JSON.parse(response.body)
        expect(body.size).to eq(2)
      end

      it 'returns profiles sorted by name' do
        create(:video_profile, name: 'Zebra')
        create(:video_profile, name: 'Alpha')

        get '/api/v1/video_profiles', as: :json
        names = JSON.parse(response.body).map { |p| p['name'] }
        expect(names).to eq(names.sort)
      end
    end
  end

  describe 'POST /api/v1/video_profiles', :without_rswag do
    context 'as admin' do
      before { sign_in admin_user }

      it 'creates a profile and returns 201' do
        post '/api/v1/video_profiles',
             params: { video_profile: { name: 'New Video Profile', encode_for_adaptive_streaming: true } },
             as: :json

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['name']).to eq('New Video Profile')
      end

      it 'creates a profile with encoding presets' do
        post '/api/v1/video_profiles',
             params: {
               video_profile: {
                 name:                          'Adaptive HD',
                 encode_for_adaptive_streaming: true,
                 encoding_presets_attributes:   [
                   { name: '720p', height: 720, video_bitrate_kbps: 3000,
                     frame_rate_fps: 30, audio_codec: 'he_aac', audio_bitrate_kbps: 128 },
                 ],
               },
             }, as: :json

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['encoding_presets'].size).to eq(1)
        expect(body['encoding_presets'][0]['name']).to eq('720p')
      end

      it 'returns 422 when name is blank' do
        post '/api/v1/video_profiles',
             params: { video_profile: { name: '' } },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to be_present
      end
    end

    context 'as regular user' do
      before { sign_in regular_user }

      it 'returns 403' do
        post '/api/v1/video_profiles',
             params: { video_profile: { name: 'Should fail' } },
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/video_profiles/:id', :without_rswag do
    context 'as admin' do
      before { sign_in admin_user }

      it 'updates the profile name' do
        patch "/api/v1/video_profiles/#{profile.id}",
              params: { video_profile: { name: 'Updated Name' } },
              as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['name']).to eq('Updated Name')
      end

      it 'updates encode_for_adaptive_streaming' do
        patch "/api/v1/video_profiles/#{profile.id}",
              params: { video_profile: { encode_for_adaptive_streaming: false } },
              as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['encode_for_adaptive_streaming']).to be(false)
      end
    end
  end

  describe 'DELETE /api/v1/video_profiles/:id', :without_rswag do
    context 'as admin' do
      before { sign_in admin_user }

      it 'soft-deletes and returns 204' do
        delete "/api/v1/video_profiles/#{profile.id}", as: :json
        expect(response).to have_http_status(:no_content)
        expect(profile.reload.deleted_at).not_to be_nil
      end

      it 'hides the profile from index after deletion' do
        delete "/api/v1/video_profiles/#{profile.id}", as: :json
        get '/api/v1/video_profiles', as: :json
        ids = JSON.parse(response.body).map { |p| p['id'] }
        expect(ids).not_to include(profile.id)
      end
    end
  end

  describe 'POST /api/v1/video_profiles/:id/copy', :without_rswag do
    context 'as admin' do
      before { sign_in admin_user }

      let!(:profile_with_presets) { create(:video_profile, :with_adaptive_presets) }

      it 'clones the profile and all its presets' do
        post "/api/v1/video_profiles/#{profile_with_presets.id}/copy",
             params: { name: 'My Copy' },
             as: :json

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['name']).to eq('My Copy')
        expect(body['encoding_presets'].size).to eq(3)
        expect(VideoProfile.active.count).to eq(2)
      end

      it 'appends " (copy)" when no name supplied' do
        post "/api/v1/video_profiles/#{profile.id}/copy", as: :json
        expect(JSON.parse(response.body)['name']).to eq("#{profile.name} (copy)")
      end
    end
  end

  describe 'POST /api/v1/video_profiles/:id/apply_to_folder', :without_rswag do
    let(:folder_id) { SecureRandom.uuid }

    context 'as admin' do
      before { sign_in admin_user }

      it 'creates a folder assignment' do
        post "/api/v1/video_profiles/#{profile.id}/apply_to_folder",
             params: { folder_id: folder_id },
             as: :json

        expect(response).to have_http_status(:created)
        expect(VideoProfileFolderAssignment.where(video_profile: profile, folder_id: folder_id)).to exist
      end

      it 'is idempotent' do
        2.times do
          post "/api/v1/video_profiles/#{profile.id}/apply_to_folder",
               params: { folder_id: folder_id },
               as: :json
        end
        expect(VideoProfileFolderAssignment.where(video_profile: profile, folder_id: folder_id).count).to eq(1)
      end

      it 'returns 400 without folder_id' do
        post "/api/v1/video_profiles/#{profile.id}/apply_to_folder", as: :json
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'DELETE /api/v1/video_profiles/:id/remove_from_folder', :without_rswag do
    let(:folder_id) { SecureRandom.uuid }

    before do
      sign_in admin_user
      VideoProfileFolderAssignment.create!(video_profile: profile, folder_id: folder_id)
    end

    it 'removes the folder assignment' do
      delete "/api/v1/video_profiles/#{profile.id}/remove_from_folder",
             params: { folder_id: folder_id },
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(VideoProfileFolderAssignment.where(video_profile: profile, folder_id: folder_id)).not_to exist
    end

    it 'is idempotent (does not error on double-remove)' do
      2.times do
        delete "/api/v1/video_profiles/#{profile.id}/remove_from_folder",
               params: { folder_id: folder_id },
               as: :json
      end
      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'Adaptive streaming validation', :without_rswag do
    before { sign_in admin_user }

    it 'returns warnings when presets have mismatched audio codecs' do
      profile_with_presets = create(:video_profile, encode_for_adaptive_streaming: true)
      create(:video_encoding_preset, video_profile: profile_with_presets,
             name: 'A', height: 360, video_bitrate_kbps: 730, audio_codec: 'he_aac')
      create(:video_encoding_preset, video_profile: profile_with_presets,
             name: 'B', height: 720, video_bitrate_kbps: 3000, audio_codec: 'aac')

      get "/api/v1/video_profiles/#{profile_with_presets.id}", as: :json
      body = JSON.parse(response.body)
      expect(body['adaptive_streaming_warnings']).not_to be_empty
    end

    it 'returns no warnings when all presets match' do
      profile_with_presets = create(:video_profile, :with_adaptive_presets)

      get "/api/v1/video_profiles/#{profile_with_presets.id}", as: :json
      body = JSON.parse(response.body)
      expect(body['adaptive_streaming_warnings']).to be_empty
    end
  end
end
