require 'capybara/rails'
require 'capybara/rspec'

# Backend E2E / feature specs run through the full Rack stack (routes →
# controllers → views) using the headless rack_test driver, so they need no
# real browser. For JavaScript-driven flows, swap to a Selenium/Playwright
# driver and pair with Coverband for runtime coverage.
Capybara.default_driver    = :rack_test
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.include Warden::Test::Helpers, type: :system

  config.before(:each, type: :system) do
    Warden.test_mode!
    driven_by :rack_test
  end

  config.after(:each, type: :system) { Warden.test_reset! }
end

