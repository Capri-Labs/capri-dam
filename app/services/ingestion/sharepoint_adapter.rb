require "net/http"
require "uri"

module IngestionAdapters
  # Microsoft SharePoint / OneDrive for Business Adapter
  # Uses Microsoft Graph API
  # API docs: https://learn.microsoft.com/en-us/graph/api/driveitem-list-children
  #
  # Credentials: endpoint (drive endpoint, e.g. https://graph.microsoft.com/v1.0/drives/{driveId}),
  #              auth_token (Azure AD OAuth2 Bearer token — application permissions required)
  class SharepointAdapter < Base
    def fetch_next_chunk(cursor = nil, limit = 100)
      # cursor holds the @odata.nextLink URL for continuation, or the folder path for first call
      url = if cursor.present? && cursor.start_with?("http")
              cursor  # Microsoft supplies a full next-page URL
      else
              folder  = credentials["folder_path"].presence || "root"
              "#{endpoint}/#{folder}/children?$top=#{limit}&$orderby=createdDateTime asc" \
              "&$select=id,name,size,file,createdDateTime,lastModifiedDateTime,parentReference"
      end

      data  = get_json(url)
      items = Array(data["value"] || []).select { |i| i.key?("file") } # files only, skip folders

      files = items.map do |item|
        {
          identifier:    item["id"],
          size:          item["size"].to_i,
          original_name: item["name"],
          metadata: {
            "title"        => item["name"],
            "content_type" => item.dig("file", "mimeType"),
            "created"      => item["createdDateTime"],
            "modified"     => item["lastModifiedDateTime"],
            "folder"       => item.dig("parentReference", "path"),
          }.compact,
        }
      end

      {
        files:       files,
        next_cursor: data["@odata.nextLink"],
        has_more:    data["@odata.nextLink"].present?,
      }
    end

    def download_and_stream(file_identifier, &block)
      # Graph API download: GET /drives/{driveId}/items/{itemId}/content
      download_url = "#{endpoint}/items/#{file_identifier}/content"
      stream_http_file(download_url, ".bin", &block)
    end

    def test_connection
      folder = credentials["folder_path"].presence || "root"
      get_json("#{endpoint}/#{folder}?$select=id,name")
      { success: true, message: "Connected to SharePoint / OneDrive at configured drive. Folder '#{folder}' accessible." }
    rescue => e
      { success: false, message: "SharePoint connection failed: #{e.message}" }
    end
  end
end
