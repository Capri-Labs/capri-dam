# frozen_string_literal: true
#
# Coverband (backend E2E / runtime coverage) helper tasks.
#
#   bundle exec rake coverband:report   # print a line-coverage summary
#   bundle exec rake coverband:clear    # reset collected runtime data
#
# Coverband is only loaded in :development and :production, so these tasks are
# no-ops under the test environment.

namespace :coverband do
  desc "Print a summary of Coverband runtime (E2E) coverage"
  task report: :environment do
    unless defined?(Coverband)
      puts "Coverband is not loaded in this environment (#{Rails.env})."
      puts "Run with RAILS_ENV=development after exercising the app via E2E."
      next
    end

    data    = Coverband.configuration.store.coverage
    total   = 0
    covered = 0

    data.each_value do |info|
      lines = info.is_a?(Hash) ? (info["data"] || info[:data] || []) : info
      Array(lines).each do |hits|
        next if hits.nil?

        total   += 1
        covered += 1 if hits.positive?
      end
    end

    pct = total.zero? ? 0.0 : (covered.to_f / total * 100).round(2)
    puts "──────────────────────────────────────────────"
    puts " Coverband backend E2E coverage"
    puts " Files tracked : #{data.size}"
    puts " Lines covered : #{covered} / #{total} (#{pct}%)"
    puts " Dashboard     : /admin/coverband (admin login)"
    puts "──────────────────────────────────────────────"
  rescue Redis::BaseConnectionError, Errno::ECONNREFUSED => e
    puts "Coverband store unreachable: #{e.message}"
    puts "Start Redis (or set COVERBAND_REDIS_URL) and exercise the app, then retry."
  end

  desc "Clear all collected Coverband runtime data"
  task clear: :environment do
    if defined?(Coverband)
      Coverband.configuration.store.clear!
      puts "Coverband runtime data cleared."
    else
      puts "Coverband not loaded in #{Rails.env}; nothing to clear."
    end
  end
end

