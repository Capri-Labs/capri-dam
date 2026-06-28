# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Assets deep-link routing', type: :routing do
  it 'routes GET /assets to dashboard#assets' do
    expect(get: '/assets').to route_to('dashboard#assets')
  end
end

RSpec.describe 'Assets deep-link integration', type: :request do
  let(:user) { FactoryBot.create(:user) }

  before { sign_in user }

  it 'renders the HTML shell for /assets' do
    get '/assets'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-view="folders"')
  end

  it 'passes the asset id as a data attribute when ?id= is present' do
    uuid = '122a787d-1dda-4573-b181-df39cbcb1022'
    get "/assets?id=#{uuid}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-initial-target-asset-id')
    expect(response.body).to include(uuid)
  end

  it 'does not include the data attribute when ?id= is absent' do
    get '/assets'
    expect(response.body).not_to include('data-initial-target-asset-id')
  end
end
