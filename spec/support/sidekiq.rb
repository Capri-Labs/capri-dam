# Configure Sidekiq for testing using the Sidekiq 8 API.
# Sidekiq.testing!(:fake) enqueues jobs into an in-memory array without
# requiring a live Redis connection.  Do NOT use `require "sidekiq/testing"` —
# that is deprecated and will be removed in Sidekiq 9.0.
require "sidekiq"

Sidekiq.testing!(:fake)

RSpec.configure do |config|
  config.before(:each) do
    Sidekiq::Job.clear_all
  end

  # Allow individual specs to switch to inline mode:
  #   include_context "sidekiq:inline"
  shared_context "sidekiq:inline" do
    around { |ex| Sidekiq.testing!(:inline) { ex.run } }
  end
end
