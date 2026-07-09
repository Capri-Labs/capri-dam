require 'rails_helper'

RSpec.describe 'Api::V1::IngestionBatches coverage', type: :request do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }

  before { sign_in user }

  describe 'GET /api/v1/ingestion_batches' do
    it 'filters by status, source type, search, and clamps invalid pages to one' do
      create(:ingestion_batch, name: 'AEM Summer', source_type: 'aem', status: :review_needed)
      create(:ingestion_batch, name: 'Other', source_type: 'cloudinary', status: :failed)

      get '/api/v1/ingestion_batches', params: { status: 'review_needed', source_type: 'aem', search: 'summer', page: 0 }, as: :json

      data = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(data['meta']).to include('total' => 1, 'page' => 1, 'per_page' => 50)
      expect(data['batches'].first['name']).to eq('AEM Summer')
    end
  end

  describe 'POST /api/v1/ingestion_batches' do
    it 'creates a batch and enqueues extraction' do
      allow(ExtractionWorker).to receive(:perform_async)

      post '/api/v1/ingestion_batches', params: { ingestion_batch: { name: 'Import', source_type: 'aem', notes: 'go', source_credentials: { token: 'redacted' } } }, as: :json

      batch = IngestionBatch.last
      expect(response).to have_http_status(:created)
      expect(batch).to be_initializing
      expect(batch.initiated_by_id).to eq(user.id)
      expect(batch.started_at).to be_present
      expect(ExtractionWorker).to have_received(:perform_async).with(batch.id)
    end

    it 'defaults migrate_metadata to true when not specified' do
      allow(ExtractionWorker).to receive(:perform_async)

      post '/api/v1/ingestion_batches', params: { ingestion_batch: { name: 'Import', source_type: 'aem' } }, as: :json

      batch = IngestionBatch.last
      expect(response).to have_http_status(:created)
      expect(batch.migrate_metadata).to be true
      expect(JSON.parse(response.body).dig('batch', 'migrate_metadata')).to be true
    end

    it 'allows opting out of full metadata migration' do
      allow(ExtractionWorker).to receive(:perform_async)

      post '/api/v1/ingestion_batches',
           params: { ingestion_batch: { name: 'Import', source_type: 'aem', migrate_metadata: false } },
           as: :json

      batch = IngestionBatch.last
      expect(response).to have_http_status(:created)
      expect(batch.migrate_metadata).to be false
      expect(JSON.parse(response.body).dig('batch', 'migrate_metadata')).to be false
    end

    it 'persists the chosen destination folder' do
      allow(ExtractionWorker).to receive(:perform_async)
      folder = create(:folder, name: 'Target')

      post '/api/v1/ingestion_batches',
           params: { ingestion_batch: { name: 'Import', source_type: 'aem', destination_folder_id: folder.id } },
           as: :json

      batch = IngestionBatch.last
      expect(response).to have_http_status(:created)
      expect(batch.destination_folder_id).to eq(folder.id)
      expect(JSON.parse(response.body)['batch']).to include(
        'destination_folder_id'   => folder.id,
        'destination_folder_name' => 'Target'
      )
    end

    it 'returns validation errors for invalid payloads' do
      post '/api/v1/ingestion_batches', params: { ingestion_batch: { name: '', source_type: '' } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors']).to include("Name can't be blank", "Source type can't be blank")
    end
  end

  describe 'GET /api/v1/ingestion_batches/:id' do
    it 'filters items by status and clamps negative pages to one' do
      batch = create(:ingestion_batch)
      wanted = create(:ingestion_item, ingestion_batch: batch, status: :flagged_error, original_filename: 'bad.jpg')
      create(:ingestion_item, ingestion_batch: batch, status: :pending, original_filename: 'pending.jpg')

      get "/api/v1/ingestion_batches/#{batch.id}", params: { status: 'flagged_error', page: -3 }, as: :json

      data = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(data['items'].map { |item| item['id'] }).to eq([ wanted.id ])
      expect(data['meta']).to include('total' => 1, 'page' => 1)
    end

    it 'returns 404 when the batch does not exist' do
      get '/api/v1/ingestion_batches/missing', as: :json

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to include('error' => 'Batch not found')
    end

    it 'includes each item\'s full_metadata (raw per-asset metadata payload) for the audit view' do
      batch = create(:ingestion_batch)
      create(:ingestion_item, ingestion_batch: batch, original_filename: 'hero.psd',
        full_metadata: { 'dc:title' => 'Hero', 'dc:description' => 'Full desc' })

      get "/api/v1/ingestion_batches/#{batch.id}", as: :json

      item = JSON.parse(response.body)['items'].first
      expect(item['full_metadata']).to eq('dc:title' => 'Hero', 'dc:description' => 'Full desc')
    end
  end

  describe 'admin-only lifecycle actions' do
    it 'returns 403 when a regular user tries to commit' do
      batch = create(:ingestion_batch, status: :review_needed)

      post "/api/v1/ingestion_batches/#{batch.id}/commit", as: :json

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('Administrator privileges required.')
    end

    it 'commits only review_needed batches for admins' do
      sign_out user
      sign_in admin
      allow(MigrationCommitWorker).to receive(:perform_async)
      batch = create(:ingestion_batch, status: :review_needed)
      blocked = create(:ingestion_batch, status: :extracting)

      post "/api/v1/ingestion_batches/#{batch.id}/commit", as: :json
      expect(response).to have_http_status(:ok)
      expect(MigrationCommitWorker).to have_received(:perform_async).with(batch.id)

      post "/api/v1/ingestion_batches/#{blocked.id}/commit", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to include("Batch must be in 'review_needed' state")
    end

    it 'aborts non-committed batches and rejects committed batches' do
      sign_out user
      sign_in admin
      batch = create(:ingestion_batch, status: :extracting)
      committed = create(:ingestion_batch, status: :committed)

      post "/api/v1/ingestion_batches/#{batch.id}/abort", as: :json
      expect(response).to have_http_status(:ok)
      expect(batch.reload).to be_failed
      expect(batch.completed_at).to be_present

      post "/api/v1/ingestion_batches/#{committed.id}/abort", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('Cannot abort a committed batch.')
    end

    it 'deletes only failed batches' do
      sign_out user
      sign_in admin
      failed = create(:ingestion_batch, status: :failed)
      active = create(:ingestion_batch, status: :extracting)

      delete "/api/v1/ingestion_batches/#{active.id}", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('Only failed batches can be deleted.')

      delete "/api/v1/ingestion_batches/#{failed.id}", as: :json
      expect(response).to have_http_status(:ok)
      expect(IngestionBatch.exists?(failed.id)).to be(false)
    end
  end

  describe 'GET /api/v1/ingestion_batches/:id/report' do
    it 'returns stored snapshot stats when present' do
      snapshot = create(:report_snapshot, parameters: { 'stats' => { 'rows' => 7 } })
      batch = create(:ingestion_batch, report_snapshot_id: snapshot.id)

      get "/api/v1/ingestion_batches/#{batch.id}/report", as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['report']).to eq('rows' => 7)
    end

    it 'queues report generation for committed batches without stats' do
      allow(MigrationReportWorker).to receive(:perform_async)
      batch = create(:ingestion_batch, status: :committed)

      get "/api/v1/ingestion_batches/#{batch.id}/report", as: :json

      expect(response).to have_http_status(:accepted)
      expect(MigrationReportWorker).to have_received(:perform_async).with(batch.id)
    end
  end

  it 'returns 401 for unauthenticated requests' do
    sign_out user

    get '/api/v1/ingestion_batches', as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'additional filtering branches' do
    it 'returns batches unchanged when no filters are supplied' do
      first = create(:ingestion_batch, name: 'One', source_type: 'aem', status: :review_needed)
      second = create(:ingestion_batch, name: 'Two', source_type: 'cloudinary', status: :failed)

      get '/api/v1/ingestion_batches', as: :json

      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body['meta']['total']).to be >= 2
      expect(body['batches'].map { |batch| batch['id'] }).to include(first.id, second.id)
    end

    it 'returns all items when no status filter is provided on show' do
      batch = create(:ingestion_batch)
      create(:ingestion_item, ingestion_batch: batch, status: :flagged_error)
      create(:ingestion_item, ingestion_batch: batch, status: :pending)

      get "/api/v1/ingestion_batches/#{batch.id}", as: :json

      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body['items'].size).to eq(2)
      expect(body['meta']['total']).to eq(2)
    end

    it 'returns an empty report when the snapshot reference is stale' do
      batch = create(:ingestion_batch, report_snapshot_id: 999_999, status: :failed)

      get "/api/v1/ingestion_batches/#{batch.id}/report", as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['report']).to eq({})
    end
  end
end
