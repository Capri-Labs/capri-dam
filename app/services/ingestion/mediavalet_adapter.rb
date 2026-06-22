require 'net/http'
require 'uri'

module IngestionAdapters
  # MediaValet DAM Adapter
  # API docs: https://api.mediavalet.com/docs
  #
  # Credentials: endpoint (e.g. https://api.mediavalet.com), auth_token (Azure AD OAuth2 Bearer)
  class MediaValetAdapter < Base
    PAGE_SIZE = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      page = cursor.to_i.zero? ? 1 : cursor.to_i
      url  = "#{endpoint}/api/v1.4/assets?page=#{page}&pageSize=#{limit}&sortBy=createdAt&sortOrder=asc"

      data  = get_json(url)
      items = Array(data.dig('payload', 'assets') || data['assets'] || [])

      files = items.map do |item|
        attrs = item['attributes'] || item
        {
          identifier:    item['id'],
          size:          attrs['fileSize'].to_i,
          original_name: attrs['filename'] || attrs['title'],
          metadata: {
            'title'        => attrs['title'],
            'description'  => attrs['description'],
            'tags'         => Array(attrs['keywords']).join(', '),
            'content_type' => attrs['mediaType'],
            'created'      => attrs['createdAt'],
            'modified'     => attrs['modifiedAt'],
            'category'     => attrs['categoryName']
          }.compact
        }
      end

      total    = data.dig('payload', 'total') || data['total'].to_i
      fetched  = (page - 1) * limit + items.size

      {
        files:       files,
        next_cursor: (page + 1).to_s,
        has_more:    fetched < total
      }
    end

    def download_and_stream(file_identifier, &block)
      data         = get_json("#{endpoint}/api/v1.4/assets/#{file_identifier}/download")
      download_url = data.dig('payload', 'downloadUrl') || data['downloadUrl']
      raise "MediaValet: no download URL for #{file_identifier}" unless download_url
      stream_http_file(download_url, '.bin', &block)
    end

    def test_connection
      get_json("#{endpoint}/api/v1.4/categories?pageSize=1")
      { success: true, message: "Connected to MediaValet at #{endpoint}." }
    rescue => e
      { success: false, message: "MediaValet connection failed: #{e.message}" }
    end
  end
end

