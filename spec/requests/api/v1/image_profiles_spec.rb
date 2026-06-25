# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Image Profiles API', type: :request do
  # ── Shared setup ─────────────────────────────────────────────────────────────
  let(:admin_user)    { create(:user, admin: true) }
  let(:regular_user)  { create(:user, admin: false) }
  let(:profile)       { create(:image_profile) }

  # ── GET /api/v1/image_profiles ───────────────────────────────────────────────
  path '/api/v1/image_profiles' do
    get 'Lists all active Image Profiles' do
      tags        'Tools - Image Profiles'
      produces    'application/json'
      security    [ Bearer: [] ]

      response '200', 'profiles retrieved successfully' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id:                      { type: :integer },
                   name:                    { type: :string },
                   crop_type:               { type: :string, enum: %w[none smart_crop] },
                   responsive_crop_enabled: { type: :boolean },
                   responsive_crops:        { type: :array,  items: { type: :object } },
                   swatch_enabled:          { type: :boolean },
                   swatch_width:            { type: :integer, nullable: true },
                   swatch_height:           { type: :integer, nullable: true },
                   folder_count:            { type: :integer },
                   unsharp_mask:            {
                     type: :object,
                     properties: {
                       amount:    { type: :number, description: 'Range: 0–5. Default: 1.75' },
                       radius:    { type: :number, description: 'Range: 0–250. Default: 0.2' },
                       threshold: { type: :integer, description: 'Range: 0–255. Default: 2' },
                     },
                   },
                   created_at: { type: :string, format: 'date-time' },
                   updated_at: { type: :string, format: 'date-time' },
                 },
               }
        run_test!
      end
    end

    post 'Creates a new Image Profile' do
      tags        'Tools - Image Profiles'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ :image_profile ],
        properties: {
          image_profile: {
            type: :object,
            required: [ :name ],
            properties: {
              name:                    { type: :string, example: 'My Profile' },
              crop_type:               { type: :string, enum: %w[none smart_crop], example: 'smart_crop' },
              responsive_crop_enabled: { type: :boolean, example: true },
              responsive_crops: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    name:   { type: :string,  example: 'Large' },
                    width:  { type: :integer, example: 1260 },
                    height: { type: :integer, example: 720 },
                  },
                },
              },
              swatch_enabled:  { type: :boolean, example: true },
              swatch_width:    { type: :integer, example: 100 },
              swatch_height:   { type: :integer, example: 100 },
              unsharp_mask: {
                type: :object,
                properties: {
                  amount:    { type: :number,  example: 1.75 },
                  radius:    { type: :number,  example: 0.2 },
                  threshold: { type: :integer, example: 2 },
                },
              },
            },
          },
        },
      }

      response '201', 'profile created' do
        schema type: :object, properties: { id: { type: :integer }, name: { type: :string } }
        run_test!
      end

      response '403', 'forbidden – admin only' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'validation failed' do
        schema type: :object,
               properties: {
                 errors: { type: :array, items: { type: :string } },
               }
        run_test!
      end
    end
  end

  # ── GET /api/v1/image_profiles/:id ──────────────────────────────────────────
  path '/api/v1/image_profiles/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true

    get 'Retrieves a single Image Profile' do
      tags     'Tools - Image Profiles'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'profile found' do
        schema type: :object,
               properties: {
                 id:      { type: :integer },
                 name:    { type: :string },
                 folders: { type: :array, items: { type: :object } },
               }
        run_test!
      end

      response '404', 'not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    patch 'Updates an Image Profile' do
      tags     'Tools - Image Profiles'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          image_profile: {
            type: :object,
            properties: {
              name:      { type: :string },
              crop_type: { type: :string, enum: %w[none smart_crop] },
            },
          },
        },
      }

      response '200', 'profile updated' do
        schema type: :object, properties: { id: { type: :integer }, name: { type: :string } }
        run_test!
      end

      response '403', 'forbidden – admin only' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    delete 'Soft-deletes an Image Profile' do
      tags     'Tools - Image Profiles'
      produces 'application/json'
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

  # ── POST /api/v1/image_profiles/:id/apply_to_folder ─────────────────────────
  path '/api/v1/image_profiles/{id}/apply_to_folder' do
    parameter name: :id, in: :path, type: :integer, required: true

    post 'Applies an Image Profile to a folder' do
      tags     'Tools - Image Profiles'
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

  # ── DELETE /api/v1/image_profiles/:id/remove_from_folder ─────────────────────
  path '/api/v1/image_profiles/{id}/remove_from_folder' do
    parameter name: :id, in: :path, type: :integer, required: true

    delete 'Removes an Image Profile from a folder' do
      tags     'Tools - Image Profiles'
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

  # ── GET /api/v1/image_profiles/:id/folders ──────────────────────────────────
  path '/api/v1/image_profiles/{id}/folders' do
    parameter name: :id, in: :path, type: :integer, required: true

    get 'Lists folders the Image Profile is applied to' do
      tags     'Tools - Image Profiles'
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

  describe 'GET /api/v1/image_profiles', :without_rswag do
    context 'as authenticated user' do
      before { sign_in admin_user }

      it 'returns 200 with an array' do
        create_list(:image_profile, 3)
        create(:image_profile, :deleted) # should not appear

        get '/api/v1/image_profiles', as: :json
        expect(response).to have_http_status(:ok)

        body = JSON.parse(response.body)
        expect(body.size).to eq(3)
      end
    end
  end

  describe 'POST /api/v1/image_profiles', :without_rswag do
    context 'as admin' do
      before { sign_in admin_user }

      it 'creates a profile and returns 201' do
        post '/api/v1/image_profiles',
             params: { image_profile: { name: 'New Profile', crop_type: 'smart_crop' } },
             as: :json

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['name']).to eq('New Profile')
      end

      it 'returns 422 when name is missing' do
        post '/api/v1/image_profiles',
             params: { image_profile: { name: '' } },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to be_present
      end
    end

    context 'as regular user' do
      before { sign_in regular_user }

      it 'returns 403' do
        post '/api/v1/image_profiles',
             params: { image_profile: { name: 'Unauthorized' } },
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/image_profiles/:id', :without_rswag do
    context 'as admin' do
      before { sign_in admin_user }

      it 'updates the profile' do
        patch "/api/v1/image_profiles/#{profile.id}",
              params: { image_profile: { name: 'Updated Name' } },
              as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['name']).to eq('Updated Name')
      end
    end
  end

  describe 'DELETE /api/v1/image_profiles/:id', :without_rswag do
    context 'as admin' do
      before { sign_in admin_user }

      it 'soft-deletes the profile and returns 204' do
        delete "/api/v1/image_profiles/#{profile.id}", as: :json
        expect(response).to have_http_status(:no_content)
        expect(profile.reload.deleted_at).not_to be_nil
      end
    end
  end

  describe 'POST /api/v1/image_profiles/:id/apply_to_folder', :without_rswag do
    let(:folder_id) { SecureRandom.uuid }

    context 'as admin' do
      before { sign_in admin_user }

      it 'creates a folder assignment' do
        post "/api/v1/image_profiles/#{profile.id}/apply_to_folder",
             params: { folder_id: folder_id },
             as: :json

        expect(response).to have_http_status(:created)
        expect(ImageProfileFolderAssignment.where(image_profile: profile, folder_id: folder_id)).to exist
      end

      it 'is idempotent on duplicate apply' do
        2.times do
          post "/api/v1/image_profiles/#{profile.id}/apply_to_folder",
               params: { folder_id: folder_id },
               as: :json
        end
        expect(ImageProfileFolderAssignment.where(image_profile: profile, folder_id: folder_id).count).to eq(1)
      end

      it 'returns 400 without folder_id' do
        post "/api/v1/image_profiles/#{profile.id}/apply_to_folder", as: :json
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'DELETE /api/v1/image_profiles/:id/remove_from_folder', :without_rswag do
    let(:folder_id) { SecureRandom.uuid }

    before do
      sign_in admin_user
      ImageProfileFolderAssignment.create!(image_profile: profile, folder_id: folder_id)
    end

    it 'removes the folder assignment' do
      delete "/api/v1/image_profiles/#{profile.id}/remove_from_folder",
             params: { folder_id: folder_id },
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(ImageProfileFolderAssignment.where(image_profile: profile, folder_id: folder_id)).not_to exist
    end
  end
end
