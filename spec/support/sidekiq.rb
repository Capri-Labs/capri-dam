# Run Sidekiq jobs in "fake" mode during the suite so `perform_async` enqueues
# into an in-memory array instead of requiring a live Redis connection.
# Individual specs can switch to `Sidekiq::Testing.inline!` when they want the
# job body to execute synchronously.
require 'sidekiq/testing'

Sidekiq::Testing.fake!

RSpec.configure do |config|
  config.before(:each) do
    Sidekiq::Worker.clear_all
  end
end
