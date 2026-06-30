# frozen_string_literal: true

module IntegrationHelpers
  def drain_sidekiq
    Sidekiq::Job.clear_all
  end

  def wait_for(timeout: 5, &block)
    deadline = Time.current + timeout

    loop do
      return if block.call

      raise "Timeout waiting for condition" if Time.current > deadline

      sleep 0.1
    end
  end

  def auth_headers(user, scopes: "write")
    _pat, raw = PersonalAccessToken.generate_for(
      user,
      name: "integration-test-#{SecureRandom.hex(4)}",
      scopes: scopes,
      expires_at: 1.hour.from_now
    )

    { "Authorization" => "Bearer #{raw}" }
  end

  def login_as_api(user, password: "password123")
    post "/users/sign_in",
         params: { user: { email: user.email, password: password } },
         headers: { "ACCEPT" => "application/json" }

    response.cookies
  end

  def json_body
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end

  config.include IntegrationHelpers, type: :integration
  config.include RSpec::Rails::RequestExampleGroup, type: :integration

  config.around(:each, type: :integration) do |example|
    DatabaseCleaner.cleaning do
      Sidekiq.testing!(:inline) { example.run }
    end
  end
end
