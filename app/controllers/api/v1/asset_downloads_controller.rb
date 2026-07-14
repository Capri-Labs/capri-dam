module Api
  module V1
    # Bulk "Download" endpoint backing the Explorer Tools-menu Download
    # overlay — the ZIP counterpart to individual asset/rendition downloads
    # (which already work via GET /api/v1/assets/local/:uuid).
    #
    # Unlike Copy/Move, Download never mutates anything — it only needs
    # +:read+ on each item's folder — so building the archive is handled
    # asynchronously by {AssetDownloadWorker} (heavy I/O, potentially many
    # files) while this controller does three things synchronously:
    #
    #   1. Validates the selection and checks +:read+ permission per item,
    #      dropping (with a per-item error) anything the user can't see.
    #   2. Recursively counts the *real* file total up front (folders are
    #      expanded) so the Explorer's progress bar has an accurate
    #      denominator from the very first poll.
    #   3. Reports whether another download is already queued/running for
    #      this user, so the UI can immediately tell them their new request
    #      has been queued rather than silently waiting.
    #
    # Once the worker finishes, the user is notified via both {Notification}
    # (bell icon) and {InboxMessage} (via {InboxDeliveryService}) with a
    # direct link to +GET /api/v1/asset_downloads/:id/download+ — so they
    # can come back later and download the ZIP with a single click, even if
    # they closed the tab that started it.
    class AssetDownloadsController < ApplicationController
      include Rails.application.routes.url_helpers

      before_action :authenticate_hybrid!
      before_action :set_download, only: [ :show, :download, :destroy ]

      # GET /api/v1/asset_downloads
      def index
        scope    = current_user.asset_downloads.not_expired.recent
        page     = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].to_i
        per_page = 25 unless [ 10, 25, 50 ].include?(per_page)

        downloads = scope.limit(per_page).offset((page - 1) * per_page)

        render json: {
          downloads: downloads.map { |d| serialize(d) },
          meta:      { total: scope.count, page: page, per_page: per_page },
        }
      end

      # GET /api/v1/asset_downloads/:id
      # Polled by the Explorer's progress dialog while a download is in
      # flight (pending/processing).
      def show
        render json: serialize(@download)
      end

      # POST /api/v1/asset_downloads
      #   { folder_ids: [1, 2], asset_ids: [10], name: "My Download" }
      def create
        folder_ids = Array(params[:folder_ids]).reject(&:blank?)
        asset_ids  = Array(params[:asset_ids]).reject(&:blank?)

        if folder_ids.empty? && asset_ids.empty?
          return render json: { error: "No folders or assets were specified." }, status: :unprocessable_entity
        end

        permitted_folder_ids, errors = filter_permitted_folders(folder_ids)
        permitted_asset_ids, asset_errors = filter_permitted_assets(asset_ids)
        errors.concat(asset_errors)

        if permitted_folder_ids.empty? && permitted_asset_ids.empty?
          return render json: { error: "You do not have permission to download the selected item(s).", errors: errors },
                         status: :unprocessable_entity
        end

        already_queued = AssetDownload.active_for(current_user).exists?
        total_items = count_items(permitted_folder_ids, permitted_asset_ids)

        download = current_user.asset_downloads.new(
          name:       params[:name].presence || default_name,
          folder_ids: permitted_folder_ids,
          asset_ids:  permitted_asset_ids,
          status:     :pending,
          total_items: total_items,
        )

        if download.save
          AssetDownloadWorker.perform_async(download.id)
          render json: serialize(download).merge(queued: already_queued, errors: errors), status: :accepted
        else
          render json: { errors: download.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/asset_downloads/:id/download
      def download
        unless @download.completed? && @download.zip_file.attached?
          return render json: { error: "Download not ready or file missing." }, status: :not_found
        end

        redirect_to rails_blob_path(@download.zip_file.blob, disposition: "attachment"), allow_other_host: false
      end

      # DELETE /api/v1/asset_downloads/:id
      def destroy
        @download.zip_file.purge if @download.zip_file.attached?
        @download.destroy
        render json: { success: true }
      end

      private

      def set_download
        @download = current_user.asset_downloads.find(params[:id])
      end

      def default_name
        "Download_#{Time.current.strftime("%Y%m%d_%H%M%S")}"
      end

      def filter_permitted_folders(folder_ids)
        errors  = []
        allowed = []

        folder_ids.each do |folder_id|
          folder = Folder.active.find_by(id: folder_id)
          if folder.nil?
            errors << { type: "folder", id: folder_id, error: "Folder not found." }
            next
          end

          unless folder_permission?(folder.parent, :read)
            errors << { type: "folder", id: folder.id, name: folder.name,
                         error: "You do not have permission to download this folder." }
            next
          end

          allowed << folder.id
        end

        [ allowed, errors ]
      end

      def filter_permitted_assets(asset_ids)
        errors  = []
        allowed = []

        asset_ids.each do |asset_id|
          asset = Asset.active.find_by(id: asset_id)
          if asset.nil?
            errors << { type: "asset", id: asset_id, error: "Asset not found." }
            next
          end

          source_folder = asset.folder_id ? Folder.find_by(id: asset.folder_id) : nil
          unless folder_permission?(source_folder, :read)
            errors << { type: "asset", id: asset.id, name: asset.title,
                         error: "You do not have permission to download this asset." }
            next
          end

          allowed << asset.id
        end

        [ allowed, errors ]
      end

      # Recursively counts the real number of files that will end up in the
      # archive — every asset in the flat +asset_ids+ list, plus every
      # descendant asset of every folder in +folder_ids+ (subfolders are
      # expanded, matching how the worker walks the tree at zip time).
      def count_items(folder_ids, asset_ids)
        total = asset_ids.size
        folder_ids.each do |folder_id|
          folder = Folder.active.find_by(id: folder_id)
          total += count_folder_items(folder) if folder
        end
        total
      end

      def count_folder_items(folder)
        count = folder.assets.active.count
        folder.children.active.each { |child| count += count_folder_items(child) }
        count
      end

      def serialize(download)
        {
          id:              download.id,
          name:            download.name,
          status:          download.status,
          total_items:     download.total_items,
          processed_items: download.processed_items,
          progress_percent: download.progress_percent,
          file_count:      download.file_count,
          byte_size:       download.byte_size,
          error_message:   download.error_message,
          created_at:      download.created_at&.strftime("%b %d, %Y at %H:%M"),
          expires_at:      download.expires_at&.strftime("%b %d, %Y"),
          download_url:    download.completed? && download.zip_file.attached? ? download_api_v1_asset_download_path(download) : nil,
        }
      end
    end
  end
end
