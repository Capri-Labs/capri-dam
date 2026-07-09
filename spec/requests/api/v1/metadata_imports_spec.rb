require 'rails_helper'

RSpec.describe 'Api::V1::MetadataImports', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def uploaded_csv(content, filename: 'metadata_import_preview.csv')
    Rack::Test::UploadedFile.new(StringIO.new(content), 'text/csv', original_filename: filename)
  end

  describe 'GET /api/v1/metadata_imports' do
    it 'returns the current user\'s non-expired imports' do
      mine    = create(:metadata_import, :completed, user: user)
      expired = create(:metadata_import, :expired, user: user)

      get '/api/v1/metadata_imports'

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |import| import['id'] }
      expect(ids).to include(mine.id)
      expect(ids).not_to include(expired.id)
    end
  end

  describe 'GET /api/v1/metadata_imports/template' do
    it 'streams the fixed-column starter CSV' do
      get '/api/v1/metadata_imports/template'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/csv')
      header = response.body.lines.first
      expect(header).to include('asset_path', 'copyright', 'tags')
    end
  end

  describe 'POST /api/v1/metadata_imports/preview' do
    before { MetadataImportWorker.clear }

    it 'returns dry-run preview results without creating an import or mutating assets' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset = create(
        :asset,
        title: 'bike.jpg',
        folder: folder,
        user: user,
        properties: { 'copyright' => 'Original', 'tags' => [ 'legacy' ] }
      )
      csv = <<~CSV
        asset_path,copyright,tags
        /Adventures/bike.jpg,ACME,bike|outdoor
        /Adventures/missing.jpg,FAIL,test
      CSV

      expect {
        post '/api/v1/metadata_imports/preview', params: {
          metadata_import: {
            source_file: uploaded_csv(csv),
            batch_size: 50,
            field_separator: ',',
            multi_value_delimiter: '|',
            launch_workflows: true,
            asset_path_column: 'asset_path',
          },
        }
      }.not_to change(MetadataImport, :count)

      expect(response).to have_http_status(:ok)
      expect(MetadataImportWorker.jobs).to be_empty

      body = response.parsed_body
      expect(body).to include(
        'dry_run' => true,
        'total_rows' => 2,
        'success_count' => 1,
        'failure_count' => 1,
        'launch_workflows' => false
      )
      expect(body['preview_csv']).to include('import_status', 'import_message')
      expect(body['rows'].first).to include(
        'row_number' => 2,
        'asset_path' => '/Adventures/bike.jpg',
        'resolved_asset_path' => '/Adventures/bike.jpg',
        'status' => 'success',
        'message' => 'Updated 2 properties'
      )
      expect(body['rows'].first['changes']).to include(
        include('field' => 'copyright', 'from' => 'Original', 'to' => 'ACME'),
        include('field' => 'tags', 'from' => [ 'legacy' ], 'to' => %w[bike outdoor])
      )
      expect(body['rows'].second).to include(
        'row_number' => 3,
        'status' => 'fail',
        'message' => "No asset found at path '/Adventures/missing.jpg'"
      )

      expect(asset.reload.properties).to eq('copyright' => 'Original', 'tags' => [ 'legacy' ])
    end

    it 'rejects preview requests without a file' do
      post '/api/v1/metadata_imports/preview', params: {
        metadata_import: {
          batch_size: 50,
          field_separator: ',',
          multi_value_delimiter: '|',
          asset_path_column: 'asset_path',
        },
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('errors' => [ 'Please select a CSV file.' ])
    end
  end

  describe 'POST /api/v1/metadata_imports' do
    let(:upload) do
      fixture_file_upload('metadata_import_sample.csv', 'text/csv')
    end

    it 'creates an import from an uploaded CSV and enqueues the worker' do
      expect {
        post '/api/v1/metadata_imports', params: {
          metadata_import: {
            source_file: upload,
            batch_size: 50,
            field_separator: ',',
            multi_value_delimiter: '|',
            asset_path_column: 'asset_path',
          },
        }
      }.to change(MetadataImportWorker.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('pending')
      expect(body['name']).to eq('metadata_import_sample.csv')
    end

    it 'rejects a request without a file' do
      post '/api/v1/metadata_imports', params: { metadata_import: { batch_size: 50 } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/metadata_imports/:id' do
    it 'destroys the import' do
      import = create(:metadata_import, user: user)
      delete "/api/v1/metadata_imports/#{import.id}"
      expect(response).to have_http_status(:ok)
      expect(MetadataImport.find_by(id: import.id)).to be_nil
    end
  end
end

# ---- merged from metadata_imports_coverage_spec.rb ----
RSpec.describe 'Api::V1::MetadataImports coverage', type: :request do
  let(:user) { create(:user) }
  let(:upload) { fixture_file_upload('metadata_import_sample.csv', 'text/csv') }

  before do
    sign_in user
    allow(MetadataImportWorker).to receive(:perform_async)
    allow(MetadataImportWorker).to receive(:perform_at)
  end

  def json = response.parsed_body

  def attach_file(import, attachment_name, filename)
    File.open(Rails.root.join('spec/fixtures/files/metadata_import_sample.csv')) do |file|
      import.public_send(attachment_name).attach(io: file, filename: filename, content_type: 'text/csv')
    end
  end

  it 'shows imports with source and result file metadata' do
    import = create(:metadata_import, :completed, user: user)
    attach_file(import, :source_file, 'source.csv')
    attach_file(import, :result_file, 'result.csv')

    get "/api/v1/metadata_imports/#{import.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(json['source_file']).to include('filename' => 'source.csv')
    expect(json['result_file']).to include('filename' => 'result.csv')
    expect(json['created_by']).to eq(user.name.presence || user.email)
  end

  it 'creates scheduled imports and normalizes comma-separated ignored columns' do
    scheduled_at = 2.days.from_now

    post '/api/v1/metadata_imports', params: {
      metadata_import: {
        name: '',
        source_file: upload,
        batch_size: 25,
        field_separator: ',',
        multi_value_delimiter: '|',
        asset_path_column: 'asset_path',
        ignored_columns: 'copyright, usage_terms, ',
        scheduled_at: scheduled_at.iso8601,
      },
    }

    expect(response).to have_http_status(:accepted)
    expect(MetadataImportWorker).to have_received(:perform_at).with(kind_of(Time), json['id'])
    expect(json).to include(
      'name' => 'metadata_import_sample.csv',
      'ignored_columns' => %w[copyright usage_terms],
      'status' => 'pending'
    )
  end

  it 'downloads source and result files and returns 404 for unavailable files' do
    import = create(:metadata_import, user: user)
    attach_file(import, :source_file, 'source.csv')

    get "/api/v1/metadata_imports/#{import.id}/download", as: :json
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include('/rails/active_storage/blobs/redirect/')

    get "/api/v1/metadata_imports/#{import.id}/download", params: { type: 'result' }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(json).to eq('error' => 'File not available.')

    attach_file(import, :result_file, 'result.csv')
    get "/api/v1/metadata_imports/#{import.id}/download", params: { type: 'result' }, as: :json
    expect(response).to have_http_status(:redirect)
  end

  it 'purges attached files when destroyed' do
    import = create(:metadata_import, user: user)
    attach_file(import, :source_file, 'source.csv')
    attach_file(import, :result_file, 'result.csv')

    delete "/api/v1/metadata_imports/#{import.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(MetadataImport.exists?(import.id)).to be(false)
    expect(json).to eq('success' => true)
  end

  it 'returns validation errors when an import cannot be saved' do
    allow_any_instance_of(MetadataImport).to receive(:save).and_return(false) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(MetadataImport).to receive_message_chain(:errors, :full_messages).and_return([ 'Nope' ]) # rubocop:disable RSpec/AnyInstance

    post '/api/v1/metadata_imports', params: {
      metadata_import: {
        source_file: upload,
        batch_size: 25,
        field_separator: ',',
        multi_value_delimiter: '|',
        asset_path_column: 'asset_path',
      },
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json).to eq('errors' => [ 'Nope' ])
  end

  it 'serializes email fallbacks and nil timestamps safely' do
    controller = Api::V1::MetadataImportsController.new
    import_without_user = build(:metadata_import)
    import_without_user.user = nil
    email_only_user = instance_double(User, name: nil, email: 'email-only@example.com')
    import_with_email = build(:metadata_import)
    allow(import_with_email).to receive(:user).and_return(email_only_user)

    expect(controller.send(:serialize, import_without_user)).to include(created_by: nil, created_at: nil)
    expect(controller.send(:serialize, import_with_email)[:created_by]).to eq('email-only@example.com')
  end
end
