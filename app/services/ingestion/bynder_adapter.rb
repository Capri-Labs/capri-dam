require "net/http"
require "uri"

module IngestionAdapters
  # Bynder DAM Adapter
  # API docs: https://bynder.docs.apiary.io/
  #
  # Credentials: endpoint (portal URL e.g. https://yourco.bynder.com), auth_token (OAuth2 Bearer)
  class BynderAdapter < Base
    PAGE_SIZE = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      page   = cursor.to_i.zero? ? 1 : cursor.to_i
      url    = "#{endpoint}/api/v4/media/?page=#{page}&count=#{limit}&orderby=dateCreated+asc"

      data  = get_json(url)
      items = Array(data)

      files = items.map do |item|
        {
          identifier:    item["id"],
          size:          item["fileSize"].to_i,
          original_name: item["name"] || item["id"],
          metadata: {
            "title"        => item["name"],
            "description"  => item["description"],
            "tags"         => Array(item["tags"]),
            "created"      => item["dateCreated"],
            "modified"     => item["dateModified"],
            "content_type" => item["extensions"]&.first,
            "copyright"    => item["copyright"],
            "campaigns"    => Array(item["campaigns"]),
          }.compact,
        }
      end

      {
        files:       files,
        next_cursor: (page + 1).to_s,
        has_more:    items.size == limit,
      }
    end

    def download_and_stream(file_identifier, &block)
      # Get download URL from Bynder
      data         = get_json("#{endpoint}/api/v4/media/#{file_identifier}/download/")
      download_url = data["s3_file"]
      raise "No download URL returned for Bynder asset #{file_identifier}" unless download_url

      stream_http_file(download_url, ".bin", &block)
    end

    def test_connection
      get_json("#{endpoint}/api/v4/account/")
      { success: true, message: "Connected to Bynder portal at #{endpoint}." }
    rescue => e
      { success: false, message: "Bynder connection failed: #{e.message}" }
    end
  end
end
