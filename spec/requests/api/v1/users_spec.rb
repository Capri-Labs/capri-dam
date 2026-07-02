require 'rails_helper'

RSpec.describe 'Api::V1::Users coverage', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'returns the first ten users ordered by name and serialized minimally' do
    create(:user, first_name: 'Zed', last_name: 'Zulu', email: 'zed@example.com', username: 'zed')
    create(:user, first_name: 'Amy', last_name: 'Alpha', email: 'amy@example.com', username: 'amy')
    create_list(:user, 11)

    get '/api/v1/users', as: :json

    data = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(data['users'].size).to eq(10)
    expect(data['users'].first).to include('username' => 'amy', 'email' => 'amy@example.com')
    expect(data['users'].first.keys).to contain_exactly('id', 'username', 'name', 'email')
  end

  it 'searches across username, email, first name, last name, and full name case-insensitively' do
    match = create(:user, username: 'DesignerOne', email: 'person@example.com', first_name: 'Casey', last_name: 'Jones', name: 'Casey Jones')
    create(:user, username: 'other', email: 'other@example.com', first_name: 'Other', last_name: 'Person', name: 'Other Person')

    get '/api/v1/users', params: { q: '  design  ' }, as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['users'].map { |entry| entry['id'] }).to include(match.id)
  end

  it 'returns 401 when unauthenticated' do
    sign_out user

    get '/api/v1/users', as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
