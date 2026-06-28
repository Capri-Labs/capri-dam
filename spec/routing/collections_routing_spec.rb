# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Collections SPA routing', type: :routing do
  # ---------------------------------------------------------------------------
  # Index route: serves the React shell for /collections
  # ---------------------------------------------------------------------------
  it 'routes GET /collections to collections#index' do
    expect(get: '/collections').to route_to('collections#index')
  end

  # ---------------------------------------------------------------------------
  # Deep-link routes: all /collections/* paths must also hit collections#index
  # so that React Router (BrowserRouter basename="/collections") can handle
  # client-side navigation after the initial HTML shell is served.
  # ---------------------------------------------------------------------------
  it 'routes GET /collections/q3-assets to collections#index (SPA catch-all)' do
    expect(get: '/collections/q3-assets').to route_to(
      controller: 'collections',
      action:     'index',
      path:       'q3-assets'
    )
  end

  it 'routes GET /collections/some-slug/nested to collections#index (nested path)' do
    expect(get: '/collections/some-slug/nested').to route_to(
      controller: 'collections',
      action:     'index',
      path:       'some-slug/nested'
    )
  end

  # ---------------------------------------------------------------------------
  # API routes must NOT be shadowed by the frontend catch-all
  # ---------------------------------------------------------------------------
  it 'routes GET /api/v1/collections to api/v1/collections#index' do
    expect(get: '/api/v1/collections').to route_to('api/v1/collections#index')
  end

  it 'routes GET /api/v1/collections/q3-assets to api/v1/collections#show' do
    expect(get: '/api/v1/collections/q3-assets').to route_to(
      controller: 'api/v1/collections',
      action:     'show',
      slug:       'q3-assets'
    )
  end
end
