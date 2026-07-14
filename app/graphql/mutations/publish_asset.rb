# frozen_string_literal: true

module Mutations
  # Direct publish/unpublish for a single asset — the GraphQL counterpart of
  # +POST /api/v1/assets/:id/publish+ / +/unpublish+ (Api::V1::AssetsController).
  #
  # When +scheduledAt+ is omitted (or in the past) the action is applied
  # immediately. When it's a future timestamp, a {ScheduledPublishAction} is
  # queued instead ("Publish Later"/"Unpublish Later") for
  # {PublishSchedulerWorker} to apply once due.
  #
  # == Arguments
  # * +uuid+        — asset UUID
  # * +action+      — +"publish"+ or +"unpublish"+
  # * +scheduledAt+ — optional ISO8601 future timestamp
  #
  # == Returns
  # * +asset+     — the updated asset (immediate actions only; null when scheduled)
  # * +scheduled+ — true when a {ScheduledPublishAction} was queued instead
  # * +errors+    — any failure messages
  class PublishAsset < Mutations::BaseMutation
    description "Directly publish or unpublish an asset, immediately or at a future time."

    argument :uuid, String, required: true
    argument :action, String, required: true,
             description: "\"publish\" or \"unpublish\"."
    argument :scheduled_at, GraphQL::Types::ISO8601DateTime, required: false,
             description: "Optional future timestamp for \"Publish/Unpublish Later\"."

    field :asset,     Types::AssetType, null: true
    field :scheduled, Boolean,          null: false
    field :errors,    [ String ],       null: false

    ACTIONS = %w[publish unpublish].freeze

    def resolve(uuid:, action:, scheduled_at: nil)
      user = context[:current_user]
      return { asset: nil, scheduled: false, errors: [ "Authentication required." ] } unless user

      unless ACTIONS.include?(action)
        return { asset: nil, scheduled: false, errors: [ "action must be one of: #{ACTIONS.join(", ")}" ] }
      end

      asset = Asset.active.find_by(uuid: uuid)
      return { asset: nil, scheduled: false, errors: [ "Asset not found." ] } unless asset

      if scheduled_at && scheduled_at.future?
        asset.scheduled_publish_actions.pending.where(action_type: action)
             .update_all(status: ScheduledPublishAction.statuses[:cancelled]) # rubocop:disable Rails/SkipsModelValidations
        asset.scheduled_publish_actions.create!(action_type: action, scheduled_at: scheduled_at, created_by: user)
        { asset: nil, scheduled: true, errors: [] }
      else
        asset.public_send("#{action}!")
        { asset: asset, scheduled: false, errors: [] }
      end
    rescue StandardError => e
      { asset: nil, scheduled: false, errors: [ e.message ] }
    end
  end
end
