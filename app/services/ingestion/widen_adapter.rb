require 'net/http'
require 'uri'

module IngestionAdapters
  # Acquia DAM (Widen Collective) Adapter
  # API docs: https://widenv2.docs.apiary.io/
  #
  # Credentials: endpoint (e.g. https://api.widencollective.com), auth_token (API key)
  class WidenAdapter < Base
    PAGE_SIZE = 100

    # Widen uses a scroll/cursor-based pagination
    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      url = "#{endpoint}/v2/assets/search?" \
            "query=*&page=#{cursor.to_i.zero? ? 0 : cursor.to_i}&pageSize=#{limit}&" \
            "expand=file_properties,metadata,embeds"

      data  = get_json(url)
      items = Array(data['items'] || [])

      files = items.map do |item|
        fp = item['file_properties'] || {}
        meta = item['metadata'] || {}
        {
          identifier:    item['id'],
          size:          fp['file_size'].to_i,
          original_name: item['filename'] || item['id'],
          metadata: {
            'title'        => item['filename'],
            'description'  => item['description'],
            'tags'         => Array(meta['keywords']).flatten,
            'content_type' => fp['format'],
            'created'      => item['created_date'],
            'modified'     => item['last_update_date'],
            'width'        => fp['image_width'],
            'height'       => fp['image_height']
          }.compact
        }
      end

      {
        files:       files,
        next_cursor: (cursor.to_i + 1).to_s,
        has_more:    items.size == limit
      }
    end

    def download_and_stream(file_identifier, &block)
      data = get_json("#{endpoint}/v2/assets/#{file_identifier}/embeds?availability=download")
      # Widen provides signed download URLs in the embed options
      download_url = data.dig('embeds', 0, 'url')
      raise "Widen: no download URL for asset #{file_identifier}" unless download_url
      stream_http_file(download_url, '.bin', &block)
    end

    def test_connection
      get_json("#{endpoint}/v2/assets/search?query=*&pageSize=1")
      { success: true, message: "Connected to Acquia DAM (Widen) at #{endpoint}." }
    rescue => e
      { success: false, message: "Widen connection failed: #{e.message}" }
    end

    protected

    def default_headers
      super.merge('X-Requested-With' => 'XMLHttpRequest')
    end
  end
end

