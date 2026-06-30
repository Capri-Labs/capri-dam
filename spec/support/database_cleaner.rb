# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do |example|
    DatabaseCleaner.strategy = example.metadata[:type] == :integration ? :truncation : :transaction
    DatabaseCleaner.start unless example.metadata[:type] == :integration
  end

  config.after(:each) do |example|
    DatabaseCleaner.clean unless example.metadata[:type] == :integration
  end
end
