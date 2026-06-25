require "net/http"
require "uri"

module IngestionAdapters
  # Canto DAM Adapter
  # API docs: https://developer.canto.com/rest-api/
  #
  # Credentials: endpoint (e.g. https://yourco.canto.com), auth_token (JWT OAuth Bearer)
  class CantoAdapter < Base
    PAGE_SIZE = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      start = cursor.to_i.zero? ? 0 : cursor.to_i
      url   = "#{endpoint}/api/v1/search?keyword=*&start=#{start}&limit=#{limit}&sortBy=time&sortDirection=ascending"

      data  = get_json(url)
      items = Array(data["results"] || [])

      files = items.map do |item|
        {
          identifier:    item["id"],
          size:          item["size"].to_i,
          original_name: item["name"] || item["id"],
          metadata: {
            "title"        => item["name"],
            "description"  => item["description"],
            "tags"         => Array(item["tag"]).flatten,
            "content_type" => item["contentType"],
            "created"      => item["created"],
            "modified"     => item["lastModified"],
            "scheme"       => item["scheme"],
            "owner"        => item["owner"],
          }.compact,
        }
      end

      {
        files:       files,
        next_cursor: (start + items.size).to_s,
        has_more:    data["found"].to_i > (start + items.size),
      }
    end

    def download_and_stream(file_identifier, &block)
      data         = get_json("#{endpoint}/api/v1/image/#{file_identifier}")
      download_url = data["url"] || data.dig("directUrlOriginal")
      raise "Canto: no direct URL for #{file_identifier}" unless download_url
      stream_http_file(download_url, ".bin", &block)
    end

    def test_connection
      get_json("#{endpoint}/api/v1/tree")
      { success: true, message: "Connected to Canto at #{endpoint}. Library tree accessible." }
    rescue => e
      { success: false, message: "Canto connection failed: #{e.message}" }
    end
  end
end
