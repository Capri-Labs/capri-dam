require "net/http"
require "uri"

module IngestionAdapters
  # Extensis Portfolio (Server/Workgroup) Adapter
  # API docs: https://www.extensis.com/portfolio/
  #
  # Credentials: endpoint (e.g. https://portfolio.yourco.com), auth_token (Bearer session token)
  class ExtensisAdapter < Base
    PAGE_SIZE = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      page = cursor.to_i.zero? ? 1 : cursor.to_i
      url  = "#{endpoint}/api/v1/assets?page=#{page}&per_page=#{limit}&sort=created_at&direction=asc"

      data  = get_json(url)
      items = Array(data["assets"] || data["data"] || [])

      files = items.map do |item|
        {
          identifier:    item["id"],
          size:          item["file_size"].to_i,
          original_name: item["filename"] || item["name"],
          metadata: {
            "title"        => item["title"] || item["name"],
            "description"  => item["description"],
            "tags"         => Array(item["keywords"]),
            "content_type" => item["mime_type"],
            "created"      => item["created_at"],
            "modified"     => item["updated_at"],
            "catalog"      => item["catalog_name"],
          }.compact,
        }
      end

      total = data["total_count"].to_i
      {
        files:       files,
        next_cursor: (page + 1).to_s,
        has_more:    (page * limit) < total,
      }
    end

    def download_and_stream(file_identifier, &block)
      download_url = "#{endpoint}/api/v1/assets/#{file_identifier}/download"
      stream_http_file(download_url, ".bin", &block)
    end

    def test_connection
      get_json("#{endpoint}/api/v1/assets?per_page=1")
      { success: true, message: "Connected to Extensis Portfolio at #{endpoint}." }
    rescue => e
      { success: false, message: "Extensis connection failed: #{e.message}" }
    end
  end
end
