module Reports
  class GenerationJob < ApplicationJob
    # Route this to a specific Sidekiq queue so massive reports
    # don't block critical emails or user signups.
    queue_as :reports

    # Enterprise Resiliency: If a database deadlock or temporary memory spike occurs,
    # ActiveJob will wait and retry up to 3 times before permanently failing.
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(snapshot_id)
      # The Orchestrator we built earlier handles the heavy lifting
      Reports::Orchestrator.execute!(snapshot_id)
    end
  end
end
