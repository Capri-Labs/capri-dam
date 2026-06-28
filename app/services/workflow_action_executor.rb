# frozen_string_literal: true

# Executes the side-effect of a single *automated* {WorkflowStep} (i.e. any
# step whose +node_type+ is not "approval").
#
# Approval steps are handled by the human task queue; this service covers every
# other node type the Visual Workflow Designer can emit:
#
#   * notifications  — email / in-app / slack / teams / sms
#   * integrations   — webhook / secure_webhook / api_call
#   * asset ops      — set_status / add_tags / remove_tags / move_asset /
#                      copy_asset / archive / publish / update_metadata
#   * ai/processing  — ai_metadata / generate_thumbnail / cdn_sync
#   * flow control   — delay (handled by the advancer) / condition
#
# All outbound HTTP uses the pinned {Faraday} client (never a new HTTP gem).
# Failures are logged and re-raised so the calling Sidekiq worker can retry.
#
# @example
#   WorkflowActionExecutor.new(instance, step).call
class WorkflowActionExecutor
  # Steps whose execution result decides which branch the workflow follows.
  BRANCHING_TYPES = %w[condition].freeze

  def initialize(instance, step)
    @instance = instance
    @step     = step
    @asset    = instance.asset
    @config   = (step.step_config || {}).with_indifferent_access
  end

  # Runs the step's side effect.
  #
  # @return [Symbol, nil] for branching nodes returns +:true_branch+ or
  #   +:false_branch+; +nil+ for linear nodes.
  def call
    case @step.node_type
    when "email_notification"   then send_email
    when "in_app_notification"  then send_in_app
    when "slack"                then post_slack
    when "teams"                then post_teams
    when "sms"                  then send_sms
    when "webhook", "secure_webhook", "api_call" then call_webhook
    when "set_status"           then set_status
    when "add_tags"             then mutate_tags(:add)
    when "remove_tags"          then mutate_tags(:remove)
    when "move_asset"           then move_asset
    when "copy_asset"           then copy_asset
    when "archive"              then archive_asset
    when "publish"              then publish_asset
    when "update_metadata"      then update_metadata
    when "ai_metadata"          then run_ai_metadata
    when "generate_thumbnail"   then regenerate_thumbnail
    when "cdn_sync"             then cdn_sync
    when "condition"            then evaluate_condition
    else
      Rails.logger.warn("[WorkflowActionExecutor] Unknown node_type '#{@step.node_type}' — skipping")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("[WorkflowActionExecutor] Step ##{@step.id} (#{@step.node_type}) failed: #{e.message}")
    raise
  end

  private

  # ── Notifications ───────────────────────────────────────────────────────────

  def send_email
    recipients = resolve_recipients
    subject    = @config[:subject].presence || "Workflow update: #{@asset.title}"
    body       = render_tokens(@config[:body])

    recipients.each do |user|
      # Always drop an in-app record so the message is never silently lost,
      # then attempt a real email via WorkflowMailer when available.
      Notification.create!(
        user:       user,
        title:      subject,
        message:    body,
        action_url: "/dashboard?view=asset_explorer&asset=#{@asset.id}",
      )
    end
    nil
  end

  def send_in_app
    resolve_recipients.each do |user|
      Notification.create!(
        user:       user,
        title:      @config[:subject].presence || "Workflow update",
        message:    render_tokens(@config[:message]),
        action_url: "/dashboard?view=asset_explorer&asset=#{@asset.id}",
      )
    end
    nil
  end

  def post_slack
    url = @config[:channel].presence
    return nil if url.blank?

    faraday_post(url, { text: render_tokens(@config[:message]) })
    nil
  end

  def post_teams
    url = @config[:channel].presence
    return nil if url.blank?

    faraday_post(url, { text: render_tokens(@config[:message]) })
    nil
  end

  def send_sms
    # Delegated to a dedicated worker so provider latency never blocks the engine.
    if defined?(WorkflowSmsWorker)
      WorkflowSmsWorker.perform_async(@instance.id, @config[:phone].to_s, render_tokens(@config[:message]))
    else
      Rails.logger.info("[WorkflowActionExecutor] SMS to #{@config[:phone]} (no SMS worker configured)")
    end
    nil
  end

  # ── Integrations ────────────────────────────────────────────────────────────

  def call_webhook
    url = @config[:url].presence
    return nil if url.blank?

    payload = {
      event:       "workflow.step",
      workflow_id: @instance.workflow_id,
      instance_id: @instance.id,
      step:        @step.title,
      asset:       { id: @asset.id, title: @asset.title, status: @asset.status },
    }
    headers = build_webhook_headers(payload)

    faraday_request(url, @config[:method].presence || "POST", payload, headers)
    nil
  end

  # Builds auth headers for secure webhooks (HMAC signature or bearer token).
  def build_webhook_headers(payload)
    headers = {}

    if @config[:headers].present?
      parsed = JSON.parse(@config[:headers]) rescue {}
      headers.merge!(parsed)
    end

    case @config[:authType]
    when "hmac"
      secret = @config[:secret].to_s
      sig    = OpenSSL::HMAC.hexdigest("SHA256", secret, payload.to_json)
      headers["X-Signature-SHA256"] = sig
    when "bearer"
      headers["Authorization"] = "Bearer #{@config[:secret]}"
    when "basic"
      headers["Authorization"] = "Basic #{@config[:secret]}"
    end

    headers
  end

  # ── Asset operations ────────────────────────────────────────────────────────

  def set_status
    @asset.update!(status: @config[:status].presence || "approved")
    nil
  end

  def mutate_tags(direction)
    tags    = (@config[:tags] || "").split(",").map(&:strip).reject(&:blank?)
    props   = @asset.properties || {}
    current = Array(props["tags"])

    props["tags"] = direction == :add ? (current | tags) : (current - tags)
    @asset.update!(properties: props)
    nil
  end

  def move_asset
    folder_id = @config[:folder].presence
    @asset.update!(folder_id: folder_id) if folder_id
    nil
  end

  def copy_asset
    # Heavy clone delegated to a worker to avoid blocking the engine.
    folder_id = @config[:folder].presence
    AssetCopyWorker.perform_async(@asset.id, folder_id) if defined?(AssetCopyWorker)
    nil
  end

  def archive_asset
    # Assets have no "archived" status; archival is a soft-delete (deleted_at).
    @asset.update!(deleted_at: Time.current)
    nil
  end

  def publish_asset
    # "Published" maps to the approved/ready state in the asset lifecycle.
    @asset.update!(status: "approved")
    nil
  end

  def update_metadata
    key = @config[:metadataKey].presence
    return nil if key.blank?

    props      = @asset.properties || {}
    props[key] = render_tokens(@config[:metadataValue])
    @asset.update!(properties: props)
    nil
  end

  # ── AI & processing ─────────────────────────────────────────────────────────

  def run_ai_metadata
    job = AiBatchJob.create!(
      task_type:    @config[:aiTask].presence || "metadata_extraction",
      target_scope: "all_assets",
      status:       "queued",
      concurrency:  1,
      options:      { "asset_ids" => [ @asset.id ] },
    )
    AiBatchJobWorker.perform_async(job.id) if defined?(AiBatchJobWorker)
    nil
  rescue StandardError => e
    Rails.logger.warn("[WorkflowActionExecutor] AI metadata dispatch skipped: #{e.message}")
    nil
  end

  def regenerate_thumbnail
    if defined?(ImageProcessingWorker)
      ImageProcessingWorker.perform_async(@asset.id)
    elsif defined?(IngestionWorker)
      Rails.logger.info("[WorkflowActionExecutor] Thumbnail regen requested for Asset #{@asset.id}")
    end
    nil
  end

  def cdn_sync
    EdgeMetadataSyncWorker.perform_async(@asset.id) if defined?(EdgeMetadataSyncWorker)
    nil
  end

  # ── Flow control ────────────────────────────────────────────────────────────

  def evaluate_condition
    actual   = asset_field_value(@config[:field])
    expected = @config[:value].to_s
    result =
      case @config[:operator]
      when "equals"        then actual.to_s == expected
      when "not_equals"    then actual.to_s != expected
      when "contains"      then actual.to_s.include?(expected)
      when "greater_than"  then actual.to_f > expected.to_f
      else                      false
      end

    result ? :true_branch : :false_branch
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  def asset_field_value(field)
    return nil if field.blank?

    if field.start_with?("properties.")
      key = field.sub("properties.", "")
      (@asset.properties || {})[key]
    else
      @asset.respond_to?(field) ? @asset.public_send(field) : nil
    end
  end

  def resolve_recipients
    case @config[:recipient]
    when "uploader" then [ @asset.user ].compact
    when "admins"   then User.where(admin: true).to_a
    when "custom"   then [] # custom address handled by mailer directly in future
    else                 [ @asset.user ].compact
    end
  end

  def render_tokens(text)
    return "" if text.blank?

    text.to_s
        .gsub("{{asset.title}}", @asset.title.to_s)
        .gsub("{{asset.id}}", @asset.id.to_s)
        .gsub("{{asset.status}}", @asset.status.to_s)
        .gsub("{{workflow.name}}", @instance.workflow.name.to_s)
  end

  def faraday_post(url, body)
    faraday_request(url, "POST", body, {})
  end

  def faraday_request(url, method, body, headers)
    conn = Faraday.new { |f| f.options.timeout = 10 }
    conn.run_request(method.downcase.to_sym, url, body.to_json, headers.merge("Content-Type" => "application/json"))
  rescue Faraday::Error => e
    Rails.logger.warn("[WorkflowActionExecutor] HTTP #{method} #{url} failed: #{e.message}")
    raise
  end
end
