# Sidekiq worker that permanently purges expired items from the Recycle Bin.
#
# == What it does
#
# 1. Reads the configurable retention policy from {Setting} (defaults below).
# 2. Acquires a distributed concurrency lock via +bin_purge_status+ Setting.
# 3. Delegates to {BinPurgeService} for the actual deletion logic, which:
#    - Skips or force-terminates assets with active workflow instances
#    - Cleans up satellite records (duplicate groups, collection memberships)
#    - Deletes physical storage files for every asset version
#    - Hard-destroys the database rows
# 4. Persists the run results and timestamp back into Settings.
# 5. Sends an in-app notification to every admin user summarising the run.
# 6. If the run fails, marks status as +"failed"+ and re-raises so Sidekiq
#    surfaces the error in the UI.
#
# == Policy keys (all stored in the +Settings+ table)
#
# | Key | Default | Description |
# |-----|---------|-------------|
# | +bin_retention_days+ | 30 | Items deleted ≥ N days ago are eligible |
# | +bin_workflow_behavior+ | +"skip"+ | +"skip"+ or +"force_terminate"+ |
# | +bin_purge_batch_size+ | 50 | +find_each+ batch size |
# | +bin_purge_notify_admins+ | true | Send in-app notification on completion |
#
# == Concurrency guard
#
# Setting +bin_purge_status+ = +"running"+ acts as a distributed lock.
# A second job that starts while one is already running exits immediately.
#
# == Queue & schedule
#
# * Queue:   +bin_purge+
# * Retries: 0  (avoid double-deleting if a job is retried mid-run)
# * Scheduled: daily at 03:00 via +config/schedule.rb+
#
# @see BinPurgeService
class BinPurgeWorker
  include Sidekiq::Worker
  sidekiq_options queue: "bin_purge", retry: 0

  # Setting key used as the distributed concurrency lock.
  LOCK_KEY = "bin_purge_status"

  # ── Defaults ──────────────────────────────────────────────────────────────
  DEFAULT_RETENTION_DAYS    = 30
  DEFAULT_WORKFLOW_BEHAVIOR = "skip"  # "skip" | "force_terminate"
  DEFAULT_BATCH_SIZE        = 50
  DEFAULT_NOTIFY_ADMINS     = true

  # ── Entry point ───────────────────────────────────────────────────────────

  def perform
    # Concurrency guard — bail if a purge is already running
    if Setting.get(LOCK_KEY).to_s == "running"
      Rails.logger.info("[BinPurge] Skipped — another purge is already running.")
      return
    end

    policy = load_policy

    # Acquire lock and stamp who triggered it (scheduled = system)
    Setting.set(LOCK_KEY, "running")
    Setting.set("bin_purge_started_at", Time.current.iso8601)

    # Only overwrite triggered_by if not already set by a manual trigger
    existing_trigger = Setting.get("bin_purge_triggered_by")
    existing_source  = existing_trigger.is_a?(Hash) ? (existing_trigger[:source] || existing_trigger["source"]) : nil
    if existing_source != "manual"
      Setting.set("bin_purge_triggered_by", {
        user_id:      nil,
        user_name:    "Scheduled (System)",
        user_email:   nil,
        triggered_at: Time.current.iso8601,
        source:       "scheduled",
      })
    end

    Rails.logger.info(
      "[BinPurge] Starting purge — retention_days=#{policy[:retention_days]}, " \
      "workflow_behavior=#{policy[:workflow_behavior]}, " \
      "batch_size=#{policy[:batch_size]}"
    )

    result = BinPurgeService.new(
      retention_days:    policy[:retention_days],
      workflow_behavior: policy[:workflow_behavior],
      batch_size:        policy[:batch_size],
    ).call

    # Persist results
    Setting.set(LOCK_KEY, "completed")
    persist_results(result, policy)

    Rails.logger.info(
      "[BinPurge] Completed — deleted=#{result.deleted}, " \
      "skipped=#{result.skipped}, failed=#{result.failed}"
    )

    # Notify admins (only when something noteworthy happened)
    if policy[:notify_admins] && results_notable?(result)
      notify_admins!(result, policy)
    end
  rescue StandardError => e
    Setting.set(LOCK_KEY, "failed")
    Rails.logger.error("[BinPurge] Run failed: #{e.class} — #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    raise
  end

  private

  # ---------------------------------------------------------------------------
  # Policy loading
  # ---------------------------------------------------------------------------

  def load_policy
    {
      retention_days:    (Setting.get("bin_retention_days")    || DEFAULT_RETENTION_DAYS).to_i,
      workflow_behavior: (Setting.get("bin_workflow_behavior") || DEFAULT_WORKFLOW_BEHAVIOR).to_s.presence || DEFAULT_WORKFLOW_BEHAVIOR,
      batch_size:        (Setting.get("bin_purge_batch_size")  || DEFAULT_BATCH_SIZE).to_i,
      notify_admins:     parse_bool(Setting.get("bin_purge_notify_admins"), DEFAULT_NOTIFY_ADMINS),
    }
  end

  def parse_bool(value, default)
    return default if value.nil?

    case value
    when true, "true", "1" then true
    when false, "false", "0" then false
    else default
    end
  end

  # ---------------------------------------------------------------------------
  # Results persistence
  # ---------------------------------------------------------------------------

  def persist_results(result, policy)
    Setting.set("bin_purge_last_ran_at", Time.current.iso8601)
    Setting.set("bin_purge_last_results", {
      deleted:                 result.deleted,
      skipped:                 result.skipped,
      failed:                  result.failed,
      storage_reclaimed_bytes: result.storage_reclaimed_bytes,
      skipped_items:           result.skipped_items.first(20),
      errors:                  result.errors.first(20),
      completed_at:            Time.current.iso8601,
      retention_days:          policy[:retention_days],
      workflow_behavior:       policy[:workflow_behavior],
    })
  end

  def results_notable?(result)
    result.deleted > 0 || result.skipped > 0 || result.failed > 0
  end

  # ---------------------------------------------------------------------------
  # Admin notification
  # ---------------------------------------------------------------------------

  def notify_admins!(result, policy)
    parts = []
    parts << "#{result.deleted} item(s) permanently deleted"  if result.deleted > 0
    parts << "#{result.skipped} item(s) skipped (active workflow)" if result.skipped > 0
    parts << "⚠️ #{result.failed} item(s) failed — check worker logs" if result.failed > 0

    message = parts.join(". ") + "."
    message += " Retention policy: #{policy[:retention_days]} days."
    message += " Workflow behavior: #{policy[:workflow_behavior]}."

    User.where(admin: true).find_each do |admin|
      Notification.create!(
        user:       admin,
        title:      "🗑️ Recycle Bin Purge Completed",
        message:    message,
        action_url: "/bin",
      )
    rescue StandardError => e
      Rails.logger.warn("[BinPurge] Failed to notify admin ##{admin.id}: #{e.message}")
    end
  end
end
