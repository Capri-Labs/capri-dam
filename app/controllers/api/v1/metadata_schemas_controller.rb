class Api::V1::MetadataSchemasController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
  before_action :authenticate_hybrid!
  before_action :set_schema, only: %i[show update destroy duplicate apply_to_folder remove_from_folder]

  # GET /api/v1/metadata_schemas
  # Returns all root schemas with their full child tree and folder counts.
  def index
    schemas = MetadataSchema.active.roots
                            .includes(:children, :folder_assignments)
                            .order(is_builtin: :desc, name: :asc)

    render json: schemas.map { |s| serialize(s, include_children: true) }
  end

  # GET /api/v1/metadata_schemas/:id
  def show
    render json: serialize(@schema, include_children: true, include_resolved_tabs: true)
  end

  # POST /api/v1/metadata_schemas
  def create
    @schema = MetadataSchema.new(schema_params)
    if @schema.save
      render json: serialize(@schema, include_children: true), status: :created
    else
      render json: { errors: @schema.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/metadata_schemas/:id
  def update
    if @schema.update(schema_params)
      render json: serialize(@schema, include_children: true, include_resolved_tabs: true), status: :ok
    else
      render json: { errors: @schema.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/metadata_schemas/:id
  def destroy
    return render json: { error: 'Built-in schemas cannot be deleted.' }, status: :forbidden if @schema.is_builtin?

    @schema.soft_delete!
    head :no_content
  end

  # POST /api/v1/metadata_schemas/:id/duplicate
  # Creates a deep copy of a schema (and its children), stripping built-in flags.
  def duplicate
    ActiveRecord::Base.transaction do
      root_copy = deep_duplicate(@schema, parent: nil, name_prefix: "Copy of ")
      render json: serialize(root_copy, include_children: true), status: :created
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/metadata_schemas/:id/apply_to_folder
  def apply_to_folder
    folder_id = params[:folder_id]
    return render json: { error: 'folder_id is required' }, status: :bad_request if folder_id.blank?

    assignment = MetadataSchemaFolderAssignment.find_or_create_by!(
      metadata_schema_id: @schema.id,
      folder_id:          folder_id
    )
    render json: { schema_id: @schema.id, folder_id: assignment.folder_id }, status: :created
  end

  # DELETE /api/v1/metadata_schemas/:id/remove_from_folder
  def remove_from_folder
    folder_id = params[:folder_id]
    MetadataSchemaFolderAssignment
      .where(metadata_schema_id: @schema.id, folder_id: folder_id)
      .destroy_all
    head :no_content
  end

  # GET /api/v1/metadata_schemas/:id/folders
  # Lists all folders the schema is applied to.
  def folders
    assignments = @schema.folder_assignments
    folder_ids  = assignments.pluck(:folder_id)
    folders     = Folder.where(id: folder_ids).select(:id, :name, :path)
    render json: folders.as_json
  end

  private

  def set_schema
    @schema = MetadataSchema.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Metadata schema not found' }, status: :not_found
  end

  def schema_params
    params.require(:metadata_schema).permit(
      :name, :description, :level, :parent_id, :mime_segment,
      tabs: {}
    )
  end

  # ── Serializer ─────────────────────────────────────────────────────────────
  def serialize(schema, include_children: false, include_resolved_tabs: false)
    data = {
      id:            schema.id,
      uuid:          schema.uuid,
      name:          schema.name,
      slug:          schema.slug,
      description:   schema.description,
      level:         schema.level,
      parent_id:     schema.parent_id,
      mime_segment:  schema.mime_segment,
      is_builtin:    schema.is_builtin,
      tabs:          schema.tabs || [],
      folder_count:  schema.folder_assignments.size,
      child_count:   schema.children.active.count,
      created_at:    schema.created_at,
      updated_at:    schema.updated_at
    }

    if include_children
      data[:children] = schema.children.active.order(mime_segment: :asc).map do |child|
        serialize(child, include_children: true)
      end
    end

    data[:resolved_tabs] = schema.resolved_tabs if include_resolved_tabs

    data
  end

  # ── Deep Duplicate Helper ──────────────────────────────────────────────────
  def deep_duplicate(schema, parent:, name_prefix: "")
    copy = schema.dup
    copy.name       = "#{name_prefix}#{schema.name}"
    copy.slug       = nil       # regenerated via callback
    copy.uuid       = nil       # regenerated via callback
    copy.is_builtin = false
    copy.parent     = parent
    copy.deleted_at = nil
    copy.save!

    schema.children.active.each do |child|
      deep_duplicate(child, parent: copy)
    end

    copy
  end
end

