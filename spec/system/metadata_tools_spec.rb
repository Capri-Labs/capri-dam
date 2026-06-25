require 'rails_helper'

# Backend E2E (feature) coverage for the Metadata Tools pages. These exercise
# the full stack: routing → authenticated controller → rendered HTML shell that
# mounts the React screens via `data-view`.
RSpec.describe 'Metadata Tools pages', type: :system do
  let(:user) { create(:user) }

  before { login_as(user, scope: :user) }

  it 'renders the Metadata Export tool shell for a signed-in user' do
    visit '/tools/metadata_exports'

    expect(page).to have_css('[data-view="metadata-exports-screen"]', visible: :all)
  end

  it 'renders the Metadata Import tool shell for a signed-in user' do
    visit '/tools/metadata_imports'

    expect(page).to have_css('[data-view="metadata-imports-screen"]', visible: :all)
  end

  it 'denies access to an anonymous visitor' do
    logout(:user)
    visit '/tools/metadata_exports'

    expect(page).to have_http_status(:unauthorized)
    expect(page).not_to have_css('[data-view="metadata-exports-screen"]', visible: :all)
  end
end
