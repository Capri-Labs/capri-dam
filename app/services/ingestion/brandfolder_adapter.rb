require "net/http"
require "uri"

module IngestionAdapters
  # Brandfolder DAM Adapter
  # API docs: https://developers.brandfolder.com/
  #
  # Credentials: endpoint (e.g. https://brandfolder.com), auth_token (API key via X-API-Key header)
  #              brandfolder_key: your brandfolder slug (required in endpoint path)
  class BrandfolderAdapter < Base
    PAGE_SIZE = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      brandfolder = credentials["brandfolder_key"]
      page        = cursor.to_i.zero? ? 1 : cursor.to_i
      url         = "#{endpoint}/api/v4/brandfolders/#{brandfolder}/assets" \
                    "?page[number]=#{page}&page[size]=#{limit}&include=attachments&fields=name,description"

      data  = get_json(url)
      items = Array(data["data"] || [])

      files = items.map do |item|
        attrs = item["attributes"] || {}
        attach = item.dig("relationships", "attachments", "data", 0) || {}
        {
          identifier:    item["id"],
          size:          attrs["file_size"].to_i,
          original_name: attrs["name"],
          metadata: {
            "title"       => attrs["name"],
            "description" => attrs["description"],
            "tags"        => Array(attrs["tags"]),
            "created"     => attrs["created_at"],
            "modified"    => attrs["updated_at"],
          }.compact,
        }
      end

      total_pages = data.dig("meta", "total_pages").to_i

      {
        files:       files,
        next_cursor: (page + 1).to_s,
        has_more:    page < total_pages,
      }
    end

    def download_and_stream(file_identifier, &block)
      brandfolder  = credentials["brandfolder_key"]
      data         = get_json("#{endpoint}/api/v4/assets/#{file_identifier}/attachments")
      attachment   = Array(data["data"]).first
      download_url = attachment&.dig("attributes", "url")
      raise "Brandfolder: no attachment URL for asset #{file_identifier}" unless download_url
      stream_http_file(download_url, ".bin", &block)
    end

    def test_connection
      brandfolder = credentials["brandfolder_key"]
      raise ArgumentError, "Brandfolder: brandfolder_key is required" if brandfolder.blank?
      get_json("#{endpoint}/api/v4/brandfolders/#{brandfolder}?fields=name")
      { success: true, message: "Connected to Brandfolder '#{brandfolder}'." }
    rescue => e
      { success: false, message: "Brandfolder connection failed: #{e.message}" }
    end

    protected

    def default_headers
      {
        "X-API-Key"    => credentials["auth_token"],
        "Accept"       => "application/json",
        "Content-Type" => "application/json",
        "User-Agent"   => "CapriDAM-Migrator/1.0",
      }
    end
  end
end
