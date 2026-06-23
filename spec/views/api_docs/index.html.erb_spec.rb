require 'rails_helper'

RSpec.describe "api_docs/index.html.erb", type: :view do
  it 'renders without raising' do
    assign(:spec_data, {})
    expect { render }.not_to raise_error
  end
end
