# frozen_string_literal: true

module Mutations
  # Manually enqueue the {BinPurgeWorker} to run immediately (admin only).
  #
  # Returns a conflict error when a purge is already running.
  class TriggerBinPurge < Mutations::BaseMutation
    description "Manually trigger the Recycle Bin purge job (admin only)."

    field :queued,  Boolean,   null: true
    field :status,  String,    null: true
    field :errors,  [ String ], null: false

    def resolve
      user = context[:current_user]
      return { queued: nil, status: nil, errors: [ "Authentication required." ] } unless user
      return { queued: nil, status: nil, errors: [ "Administrator privileges required." ] } unless user.admin?

      current_status = Setting.get(BinPurgeWorker::LOCK_KEY).to_s

      if %w[running queued].include?(current_status)
        return {
          queued: false,
          status: current_status,
          errors: [ "A purge is already #{current_status}. Please wait for it to finish." ],
        }
      end

      Setting.set(BinPurgeWorker::LOCK_KEY, "queued")
      Setting.set("bin_purge_triggered_by", {
        user_id:      user.id,
        user_name:    user.name,
        user_email:   user.email,
        triggered_at: Time.current.iso8601,
        source:       "manual",
      })
      Setting.set("bin_purge_started_at", Time.current.iso8601)
      BinPurgeWorker.perform_async

      { queued: true, status: "queued", errors: [] }
    rescue StandardError => e
      { queued: nil, status: nil, errors: [ e.message ] }
    end
  end
end
