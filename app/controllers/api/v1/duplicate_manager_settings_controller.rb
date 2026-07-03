# REST API controller for the Duplicate Manager settings.
#
# Settings are stored in the +settings+ table via the {Setting} model.
# Keys managed here:
#
# * +duplicate_manager_enabled+             — Boolean (default: false)
# * +duplicate_manager_inbox_notifications+ — Boolean (default: true)
# * +duplicate_manager_scan_status+         — idle | queued | running | completed | failed
# * +duplicate_manager_last_scan_at+        — ISO-8601 timestamp of last successful scan
# * +duplicate_manager_scan_progress+       — JSON { processed:, total:, started_at:, … }
#
# == Endpoints
#
# | Method | Path                                           | Action         | Description                           |
# |--------|------------------------------------------------|----------------|---------------------------------------|
# | GET    | /api/v1/duplicate_manager_settings             | show           | Fetch current settings + scan status  |
# | PATCH  | /api/v1/duplicate_manager_settings             | update         | Save settings (admin); triggers scan  |
# | GET    | /api/v1/duplicate_manager_settings/scan_status | scan_status    | Live scan progress                    |
# | POST   | /api/v1/duplicate_manager_settings/trigger_scan| trigger_scan   | Manually start a full repo scan       |
#
# Enabling duplicate detection automatically enqueues a full repository
# scan via {DuplicateRepositoryScanWorker} so existing assets are analysed.
#
# @see DuplicateDetectionService
# @see DuplicateRepositoryScanWorker
module Api
  module V1
    class DuplicateManagerSettingsController < ApplicationController
      before_action :authenticate_hybrid!

      # GET /api/v1/duplicate_manager_settings
      #
      # @return [void] JSON with settings + scan status
      def show
        render json: current_settings
      end

      # PATCH /api/v1/duplicate_manager_settings
      #
      # Accepted parameters:
      # * +enabled+              — Boolean
      # * +inbox_notifications+  — Boolean
      #
      # When +enabled+ transitions from false → true, a full repository scan
      # is automatically queued via {DuplicateRepositoryScanWorker}.
      #
      # @return [void] renders updated settings or +403 Forbidden+
      def update
        unless current_user.admin?
          return render json: { error: "Administrator privileges required." },
                        status: :forbidden
        end

        was_enabled = detection_enabled?

        if params.key?(:enabled)
          Setting.set("duplicate_manager_enabled", params[:enabled].in?([ true, "true", "1" ]))
        end

        if params.key?(:inbox_notifications)
          Setting.set(
            "duplicate_manager_inbox_notifications",
            params[:inbox_notifications].in?([ true, "true", "1" ])
          )
        end

        # Auto-trigger a full repository scan when enabling for the first time.
        newly_enabled = !was_enabled && detection_enabled?
        if newly_enabled
          enqueue_scan!
        end

        render json: current_settings.merge(
          message:      "Settings saved successfully.",
          scan_queued:  newly_enabled,
        )
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/v1/duplicate_manager_settings/scan_status
      #
      # Returns the live scan status for the progress indicator in the UI.
      #
      # @return [void] JSON +{ status:, progress:, last_scan_at: }+
      def scan_status
        render json: current_scan_status
      end

      # POST /api/v1/duplicate_manager_settings/trigger_scan
      #
      # Admin-only: manually kick off a full repository scan.  Returns 422 if
      # detection is disabled or a scan is already running/queued.
      #
      # @return [void] JSON +{ message:, status: }+
      def trigger_scan
        unless current_user.admin?
          return render json: { error: "Administrator privileges required." },
                        status: :forbidden
        end

        unless detection_enabled?
          return render json: {
            error: "Enable duplicate detection before triggering a scan.",
          }, status: :unprocessable_entity
        end

        current_status = Setting.get("duplicate_manager_scan_status")
        if current_status.to_s == "running" && DuplicateRepositoryScanWorker.scan_running?
          return render json: {
            error:  "A scan is already running. Please wait for it to finish.",
            status: "running",
          }, status: :unprocessable_entity
        elsif current_status.to_s == "queued"
          return render json: {
            error:  "A scan is already queued. Please wait for it to finish.",
            status: "queued",
          }, status: :unprocessable_entity
        end

        enqueue_scan!
        render json: {
          message: "Full repository scan has been queued.",
          status:  "queued",
        }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      # ---------------------------------------------------------------------------
      # Helpers
      # ---------------------------------------------------------------------------
      # @return [Boolean]
      def detection_enabled?
        val = Setting.get("duplicate_manager_enabled")
        val == true || val == "true"
      end

      # Queues the scan worker and sets status to "queued".
      # @return [void]
      def enqueue_scan!
        Setting.set("duplicate_manager_scan_status", "queued")
        DuplicateRepositoryScanWorker.perform_async
      end

      # @return [Hash]
      def current_settings
        enabled = Setting.get("duplicate_manager_enabled")
        notifs  = Setting.get("duplicate_manager_inbox_notifications")

        current_settings_hash(enabled, notifs).merge(current_scan_status)
      end

      def current_settings_hash(enabled, notifs)
        {
          enabled:             enabled == true || enabled == "true",
          inbox_notifications: notifs.nil? || notifs == true || notifs == "true",
          max_display_groups:  DuplicateGroup::DISPLAY_LIMIT,
        }
      end

      # @return [Hash]
      def current_scan_status
        # Reclaims a stuck "running" lock left behind by a crashed/killed
        # worker process before reading, so the UI never shows a
        # permanently-spinning progress bar.
        DuplicateRepositoryScanWorker.scan_running? if Setting.get("duplicate_manager_scan_status").to_s == "running"

        raw_status   = Setting.get("duplicate_manager_scan_status")
        raw_progress = Setting.get("duplicate_manager_scan_progress")
        last_scan_at = Setting.get("duplicate_manager_last_scan_at")

        progress = case raw_progress
        when Hash then raw_progress
        else {}
        end

        {
          scan_status:   raw_status.to_s.presence || "idle",
          scan_progress: progress,
          last_scan_at:  last_scan_at,
        }
      end
    end
  end
end
