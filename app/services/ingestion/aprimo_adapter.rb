require 'net/http'
require 'uri'

module IngestionAdapters
  # Aprimo DAM Adapter
  # API docs: https://developers.aprimo.com/dam/
  #
  # Credentials: endpoint (e.g. https://yourco.aprimo.com), auth_token (OAuth2 Bearer)
  class AprimoAdapter < Base
    PAGE_SIZE = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      offset = cursor.to_i.zero? ? 0 : cursor.to_i
      url    = "#{endpoint}/api/dam/v1/assets?offset=#{offset}&limit=#{limit}&sortBy=createdOn&sortOrder=ASC"

      data  = get_json(url)
      items = Array(data['items'] || [])

      files = items.map do |item|
        {
          identifier:    item['id'],
          size:          item['fileSize'].to_i,
          original_name: item['fileName'] || item['title'],
          metadata: {
            'title'        => item['title'],
            'description'  => item['description'],
            'tags'         => Array(item['tags']&.map { |t| t['name'] }),
            'content_type' => item['mimeType'],
            'created'      => item['createdOn'],
            'modified'     => item['modifiedOn'],
            'record_id'    => item['recordId']
          }.compact
        }
      end

      {
        files:       files,
        next_cursor: (offset + items.size).to_s,
        has_more:    items.size == limit
      }
    end

    def download_and_stream(file_identifier, &block)
      data         = get_json("#{endpoint}/api/dam/v1/assets/#{file_identifier}/download")
      download_url = data['downloadUrl']
      raise "Aprimo: no download URL for #{file_identifier}" unless download_url
      stream_http_file(download_url, '.bin', &block)
    end

    def test_connection
      get_json("#{endpoint}/api/dam/v1/assets?limit=1")
      { success: true, message: "Connected to Aprimo DAM at #{endpoint}." }
    rescue => e
      { success: false, message: "Aprimo connection failed: #{e.message}" }
    end
  end
end

