module Api
  module V1
    class AssetsController < ActionController::API
      # This line forces OAuth protection on every action
      before_action :doorkeeper_authorize!

      def search
        # 1. Base Query (Cloud Agnostic logic)
        @assets = Asset.where(status: 'ready')

        # 2. Filter by Title (Simple search)
        if params[:q].present?
          @assets = @assets.where("title ILIKE ?", "%#{params[:q]}%")
        end

        # 3. Filter by Metadata (JSONB Search)
        # Example: ?format=JPEG
        if params[:format].present?
          @assets = @assets.where("properties ->> 'format' = ?", params[:format])
        end

        # 4. Return JSON
        render json: {
          total: @assets.count,
          results: @assets.map { |asset| format_asset(asset) }
        }
      end

      # POST /api/v1/assets
      def create
        file = params[:file]

        if file.respond_to?(:path)
          # 1. Create the Asset record
          asset = Asset.create!(
            user: current_resource_owner, # Helper method for Doorkeeper
            folder: Folder.find_or_create_by(name: "Incoming"),
            title: params[:title] || file.original_filename,
            status: 'pending',
            uuid: SecureRandom.uuid,
            properties: {
              content_type: file.content_type,
              original_filename: file.original_filename,
              size: file.size
            }
          )

          # 2. Save the file to a temporary "staging" area
          # Sidekiq can't "see" the tempfile in memory, so we save it to disk first
          staging_path = Rails.root.join('tmp', 'uploads', "#{asset.uuid}_#{file.original_filename}")
          FileUtils.mkdir_p(File.dirname(staging_path))
          FileUtils.cp(file.path, staging_path)

          # 3. Trigger the worker with the staging path
          AssetProcessorWorker.perform_async(asset.id, staging_path.to_s)

          render json: { id: asset.uuid, status: 'processing' }, status: :accepted
        else
          render json: { error: "No file provided" }, status: :unprocessable_entity
        end
      end

      private

      def current_resource_owner
        if doorkeeper_token.resource_owner_id.present?
          User.find(doorkeeper_token.resource_owner_id)
        else
          # Fallback to the first user as the 'owner' for API uploads
          User.first
        end
      end

      def format_asset(asset)
        {
          id: asset.uuid,
          title: asset.title,
          metadata: asset.properties,
          # Here we would generate the Fastly URL
          url: "https://cdn.yourdam.com/assets/#{asset.uuid}?auto=webp"
        }
      end
    end
  end
end