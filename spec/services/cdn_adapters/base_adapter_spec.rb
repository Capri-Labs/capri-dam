require 'rails_helper'

RSpec.describe CdnAdapters::BaseAdapter, type: :service do
  subject(:adapter) { described_class.new(api_token: 'token') }

  it 'raises for purge_tag' do
    expect { adapter.purge_tag('tag') }.to raise_error(NotImplementedError)
  end

  it 'raises for purge_batch' do
    expect { adapter.purge_batch(['tag']) }.to raise_error(NotImplementedError)
  end

  it 'raises for sync_metadata' do
    expect { adapter.sync_metadata('uuid', '{}') }.to raise_error(NotImplementedError)
  end
end
