# frozen_string_literal: true

module Mutations
  # Update the Recycle Bin automatic purge retention policy (admin only).
  #
  # All fields are optional — omit any you do not wish to change.
  class UpdateBinRetentionPolicy < Mutations::BaseMutation
    description "Update the Recycle Bin purge policy (admin only)."

    argument :retention_days,    Integer, required: false,
             description: "Items deleted ≥ N days ago are eligible for permanent removal (1–365)."
    argument :workflow_behavior, String,  required: false,
             description: '"skip" or "force_terminate"'
    argument :batch_size,        Integer, required: false,
             description: "DB find_each batch size (1–500)."
    argument :notify_admins,     Boolean, required: false,
             description: "Send in-app admin notification after each purge run."

    field :policy, Types::BinRetentionPolicyType, null: true
    field :errors, [ String ], null: false

    def resolve(retention_days: nil, workflow_behavior: nil, batch_size: nil, notify_admins: nil)
      user = context[:current_user]
      return { policy: nil, errors: [ "Authentication required." ] } unless user
      return { policy: nil, errors: [ "Administrator privileges required." ] } unless user.admin?

      if retention_days
        clamped = retention_days.clamp(1, 365)
        Setting.set("bin_retention_days", clamped)
      end

      if workflow_behavior
        unless %w[skip force_terminate].include?(workflow_behavior)
          return { policy: nil, errors: [ 'workflow_behavior must be "skip" or "force_terminate".' ] }
        end
        Setting.set("bin_workflow_behavior", workflow_behavior)
      end

      if batch_size
        Setting.set("bin_purge_batch_size", batch_size.clamp(1, 500))
      end

      unless notify_admins.nil?
        Setting.set("bin_purge_notify_admins", notify_admins)
      end

      { policy: build_policy, errors: [] }
    rescue StandardError => e
      { policy: nil, errors: [ e.message ] }
    end

    private

    def build_policy
      {
        retention_days:    (Setting.get("bin_retention_days")    || BinPurgeWorker::DEFAULT_RETENTION_DAYS).to_i,
        workflow_behavior: (Setting.get("bin_workflow_behavior") || BinPurgeWorker::DEFAULT_WORKFLOW_BEHAVIOR).to_s,
        batch_size:        (Setting.get("bin_purge_batch_size")  || BinPurgeWorker::DEFAULT_BATCH_SIZE).to_i,
        notify_admins:     Setting.get("bin_purge_notify_admins").nil? ? BinPurgeWorker::DEFAULT_NOTIFY_ADMINS : (Setting.get("bin_purge_notify_admins").to_s == "true"),
        next_scheduled_at: nil,
      }
    end
  end
end
