require "net/http"
require "uri"

module IngestionAdapters
  # Adobe Experience Manager Assets Adapter
  # API docs: https://experienceleague.adobe.com/docs/experience-manager-65/assets/extending/mac-api-assets.html
  #
  # Credentials: endpoint (AEM Author URL), auth_token (Bearer service token or Basic base64)
  class AemAdapter < Base
    PAGE_SIZE = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      start_offset = cursor.to_i
      url = "#{endpoint}/api/assets/content/dam.json?start=#{start_offset}&count=#{limit}&orderby=jcr:created&orderdir=asc"

      data  = get_json(url)
      items = Array(data.dig("entities") || data.dig("assets") || [])

      files = items.map do |item|
        props = item["properties"] || {}
        {
          identifier:    item["links"]&.find { |l| l["rel"]&.include?("self") }&.dig("href") || item["id"],
          size:          props["dam:size"].to_i,
          original_name: item["name"] || props["dc:title"],
          metadata: {
            "title"        => props["dc:title"],
            "description"  => props["dc:description"],
            "tags"         => Array(props["cq:tags"]),
            "creator"      => props["dc:creator"],
            "created"      => props["jcr:created"],
            "content_type" => props["dam:mimeType"],
          }.compact,
        }
      end

      {
        files:       files,
        next_cursor: (start_offset + items.size).to_s,
        has_more:    items.size == limit,
      }
    end

    def download_and_stream(file_identifier, &block)
      # AEM download URL: /path/to/asset/jcr:content/renditions/original
      download_url = file_identifier.end_with?("/jcr:content/renditions/original") ?
                     file_identifier :
                     "#{file_identifier}/jcr:content/renditions/original"

      ext = File.extname(file_identifier).presence || ".bin"
      stream_http_file("#{endpoint}#{download_url}", ext, &block)
    end

    def test_connection
      # Try to fetch the root DAM folder metadata
      get_json("#{endpoint}/api/assets/content/dam.json?count=1")
      { success: true, message: "Connected to AEM at #{endpoint}. DAM folder accessible." }
    rescue => e
      { success: false, message: "AEM connection failed: #{e.message}" }
    end
  end
end
