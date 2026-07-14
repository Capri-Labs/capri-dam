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
  BRANCHING_TYPES = %w[condition switch].freeze

  def initialize(instance, step)
    @instance = instance
    @step     = step
    @asset    = instance.asset
    @config   = (step.step_config || {}).with_indifferent_access
  end

  # Runs the step's side effect.
  #
  # @return [Symbol, Array, nil] for branching nodes returns +:true_branch+ /
  #   +:false_branch+ (condition) or +[:branch, "<handle>"]+ (switch / branching
  #   plugins); +nil+ for linear nodes; +:delay_scheduled+ for delay nodes.
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
    when "delay"                then handle_delay
    when "condition"            then evaluate_condition
    when "switch"               then evaluate_switch
    else
      if @step.node_type.to_s.start_with?("plugin:")
        execute_custom_node
      else
        Rails.logger.warn("[WorkflowActionExecutor] Unknown node_type '#{@step.node_type}' — skipping")
        nil
      end
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
      Notification.create!(
        user:       user,
        title:      subject,
        message:    body,
        action_url: "/assets?id=#{@asset.uuid || @asset.id}",
      )
    end

    # Fire the real email through the centralized notification dispatcher
    # (deliver_later uses Sidekiq under the hood). Routing exclusively through
    # CentralNotificationMailer guarantees the validated database SMTP
    # configuration is applied before every transmission.
    recipients.each do |user|
      CentralNotificationMailer.deliver_workflow_alert(
        to:       user.email,
        cc:       @config[:cc].presence,
        subject:  subject,
        body:     body,
        priority: @config[:priority].presence || "normal",
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
        action_url: "/assets?id=#{@asset.uuid || @asset.id}",
      )
    end
    nil
  end

  def post_slack
    url = @config[:channel].presence
    return nil if url.blank?

    payload = {
      attachments: [ {
        color:    @config[:color].presence || "good",
        text:     render_tokens(@config[:message]),
        fallback: render_tokens(@config[:message]),
      } ],
    }
    faraday_post(url, payload)
    nil
  end

  def post_teams
    url = @config[:channel].presence
    return nil if url.blank?

    payload = {
      "@type": "MessageCard",
      "@context": "https://schema.org/extensions",
      themeColor: teams_theme_color(@config[:color]),
      title:     render_tokens(@config[:teamsTitle] || @config[:title] || "Workflow Update"),
      text:      render_tokens(@config[:message]),
    }
    faraday_post(url, payload)
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
    @asset.update!(status: "approved", published_at: Time.current)
    # If the PublishNode configured CDN sync, fire it immediately
    cdn_sync if @config[:cdnSync] != false
    nil
  end

  def update_metadata
    props = @asset.properties || {}

    # Multi-pair format from MetadataUpdateNode: { pairs: [{key, value}, …] }
    if @config[:pairs].is_a?(Array)
      @config[:pairs].each do |pair|
        key = pair[:key].presence || pair["key"].presence
        next if key.blank?

        props[key] = render_tokens(pair[:value].presence || pair["value"])
      end
    else
      # Legacy single key-value from old step configs
      key = @config[:metadataKey].presence
      return nil if key.blank?

      props[key] = render_tokens(@config[:metadataValue])
    end

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

  # Schedules WorkflowDelayWorker to resume the instance after the configured
  # duration.  Returns a sentinel symbol so the advancer knows to stop
  # advancing — the delay worker will re-enqueue the advancer.
  def handle_delay
    value = (@config[:delayValue].presence || 1).to_i
    unit  = @config[:delayUnit].presence || "hours"

    delay_seconds =
      case unit
      when "minutes" then value * 60
      when "hours"   then value * 3600
      when "days"    then value * 86_400
      else                value * 3600
      end

    WorkflowDelayWorker.perform_in(delay_seconds, @instance.id, @step.id)
    :delay_scheduled
  end

  def evaluate_condition
    actual = asset_field_value(@config[:field])
    compare_values(actual, @config[:operator], @config[:value]) ? :true_branch : :false_branch
  end

  # Multi-way switch/case branching. Evaluates +field+ against an ordered list of
  # cases and routes to the first matching case's labelled output handle, falling
  # back to +default_label+ (default "default") when no case matches.
  #
  # Config shape:
  #   { field:, default_label:, cases: [{ operator:, value:, label: }, ...] }
  #
  # @return [Array(Symbol, String)] +[:branch, "<handle-id>"]+
  def evaluate_switch
    actual = asset_field_value(@config[:field])
    cases  = Array(@config[:cases])

    matched_index = cases.find_index do |c|
      c = c.with_indifferent_access
      compare_values(actual, c[:operator], c[:value])
    end

    label =
      if matched_index
        matched = cases[matched_index].with_indifferent_access
        matched[:label].presence || "case_#{matched_index + 1}"
      else
        @config[:default_label].presence || "default"
      end

    [ :branch, label.to_s ]
  end

  # Shared comparator used by both condition and switch evaluation.
  def compare_values(actual, operator, expected)
    expected = expected.to_s
    case operator.to_s
    when "equals"       then actual.to_s == expected
    when "not_equals"   then actual.to_s != expected
    when "contains"     then actual.to_s.include?(expected)
    when "starts_with"  then actual.to_s.start_with?(expected)
    when "ends_with"    then actual.to_s.end_with?(expected)
    when "greater_than" then actual.to_f > expected.to_f
    when "less_than"    then actual.to_f < expected.to_f
    else                     false
    end
  end

  # Dispatches a custom-node (plugin SDK) step. Execution is delegated to the
  # customer's registered HTTPS endpoint via {CustomNodeExecutor} (SSRF-guarded,
  # HMAC-signed, whitelisted response actions — no in-process code execution).
  # No-ops gracefully when the plugin SDK is not installed/registered.
  def execute_custom_node
    unless defined?(CustomNodeExecutor)
      Rails.logger.warn("[WorkflowActionExecutor] Plugin '#{@step.node_type}' — CustomNodeExecutor unavailable, skipping")
      return nil
    end

    CustomNodeExecutor.new(@instance, @step, @config).call
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

    asset_url = "/assets/#{@asset.id}"

    text.to_s
        .gsub("{{asset.title}}",      @asset.title.to_s)
        .gsub("{{asset.id}}",         @asset.id.to_s)
        .gsub("{{asset.status}}",     @asset.status.to_s)
        .gsub("{{asset.url}}",        asset_url)
        .gsub("{{workflow.name}}",    @instance.workflow.name.to_s)
  end

  def teams_theme_color(color)
    case color
    when "warning"   then "FF8C00"
    when "attention" then "FF0000"
    else                  "00B050" # good / green
    end
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
