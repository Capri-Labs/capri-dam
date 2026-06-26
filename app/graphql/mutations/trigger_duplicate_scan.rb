# frozen_string_literal: true

module Mutations
  # GraphQL mutation to trigger a full repository scan for duplicate assets.
  #
  # The mutation enqueues {DuplicateRepositoryScanWorker} which analyses every
  # non-deleted {Asset} in the repository and creates {DuplicateGroup} records
  # for assets that share an identical SHA-256 checksum.
  #
  # NOTE: Multiple *versions* of the same asset that share a checksum are
  # intentionally NOT flagged as duplicates — only different assets are.
  #
  # == Returns
  #
  # * +status+  — +"queued"+ when the scan is successfully enqueued
  # * +message+ — human-readable confirmation
  # * +errors+  — validation / auth error messages
  class TriggerDuplicateScan < Mutations::BaseMutation
    description "Queue a full repository scan for duplicate assets (admin only)."

    field :status,  String,   null: true
    field :message, String,   null: true
    field :errors,  [ String ], null: false

    def resolve
      user = context[:current_user]

      return { status: nil, message: nil, errors: [ "Authentication required." ] } unless user
      return { status: nil, message: nil, errors: [ "Administrator privileges required." ] } unless user.admin?

      unless detection_enabled?
        return {
          status:  nil,
          message: nil,
          errors:  [ "Enable duplicate detection before triggering a scan." ],
        }
      end

      current_status = Setting.get("duplicate_manager_scan_status").to_s
      if %w[running queued].include?(current_status)
        return {
          status:  current_status,
          message: nil,
          errors:  [ "A scan is already #{current_status}. Please wait for it to finish." ],
        }
      end

      Setting.set("duplicate_manager_scan_status", "queued")
      DuplicateRepositoryScanWorker.perform_async

      { status: "queued", message: "Full repository scan has been queued.", errors: [] }
    rescue StandardError => e
      { status: nil, message: nil, errors: [ e.message ] }
    end

    private

    def detection_enabled?
      val = Setting.get("duplicate_manager_enabled")
      val == true || val == "true"
    end
  end
end
