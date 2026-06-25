# config/puma.rb

# --- THREADS (Concurrency within a single process) ---
# For I/O heavy applications, 5 threads is the industry-standard sweet spot.
# Going higher introduces Global VM Lock (GVL) contention in CRuby, degrading latency.
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# --- WORKERS (Clustered Mode for true parallel execution) ---
# Set WEB_CONCURRENCY in your production environment to match physical CPU cores.
# e.g., A 4-core AWS EC2 instance should have WEB_CONCURRENCY=4.
worker_count = ENV.fetch("WEB_CONCURRENCY") { 0 }.to_i

if worker_count > 0
  workers worker_count

  # Copy-on-Write (CoW): Master process loads the app into memory BEFORE forking workers.
  # This drastically reduces RAM usage and ensures predictable, stable scaling.
  preload_app!
end

# --- PORT & ENVIRONMENT ---
port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "development" }

# --- OPERATIONAL GOVERNANCE ---
# Worker Timeout: Kills workers if they hang during heavy asset uploads.
# Prevents a single stuck request from taking down a whole CPU core.
worker_timeout ENV.fetch("PUMA_WORKER_TIMEOUT") { 60 }.to_i

# Connection Re-establishment: When workers fork, they need their own DB connections.
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Specify the PID file.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
