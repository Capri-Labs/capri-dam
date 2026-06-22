require 'net/http'
require 'uri'
require 'base64'

module IngestionAdapters
  # Cloudinary DAM Adapter
  # API docs: https://cloudinary.com/documentation/admin_api
  #
  # Credentials: cloud_name, access_key (api_key), secret_key (api_secret)
  # Uses HTTP Basic auth: api_key:api_secret
  class CloudinaryAdapter < Base
    CLOUDINARY_API = 'https://api.cloudinary.com/v1_1'
    PAGE_SIZE      = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      cloud  = credentials['cloud_name']
      url    = "#{CLOUDINARY_API}/#{cloud}/resources/image?max_results=#{limit}"
      url   += "&next_cursor=#{cursor}" if cursor.present?

      data  = get_json(url)
      items = Array(data['resources'] || [])

      files = items.map do |item|
        {
          identifier:    item['public_id'],
          size:          item['bytes'].to_i,
          original_name: "#{item['public_id']}.#{item['format']}",
          metadata: {
            'title'        => item['public_id'].split('/').last,
            'content_type' => "image/#{item['format']}",
            'width'        => item['width'],
            'height'       => item['height'],
            'created'      => item['created_at'],
            'folder'       => item['folder'],
            'tags'         => Array(item['tags'])
          }.compact
        }
      end

      {
        files:       files,
        next_cursor: data['next_cursor'],
        has_more:    data['next_cursor'].present?
      }
    end

    def download_and_stream(file_identifier, &block)
      cloud        = credentials['cloud_name']
      # Cloudinary asset URL format: /image/upload/{public_id}
      download_url = "https://res.cloudinary.com/#{cloud}/image/upload/#{file_identifier}"
      stream_http_file(download_url, ".#{file_identifier.split('.').last}", &block)
    end

    def test_connection
      cloud = credentials['cloud_name']
      raise ArgumentError, "cloud_name is required" if cloud.blank?
      get_json("#{CLOUDINARY_API}/#{cloud}/usage")
      { success: true, message: "Connected to Cloudinary cloud '#{cloud}'." }
    rescue => e
      { success: false, message: "Cloudinary connection failed: #{e.message}" }
    end

    protected

    # Cloudinary uses HTTP Basic auth (api_key:api_secret)
    def default_headers
      encoded = Base64.strict_encode64("#{credentials['access_key']}:#{credentials['secret_key']}")
      {
        'Authorization' => "Basic #{encoded}",
        'Accept'        => 'application/json',
        'User-Agent'    => 'CapriDAM-Migrator/1.0'
      }
    end
  end
end

