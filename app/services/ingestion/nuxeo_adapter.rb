require 'net/http'
require 'uri'

module IngestionAdapters
  # Nuxeo Platform Adapter
  # API docs: https://doc.nuxeo.com/rest-api/
  #
  # Credentials: endpoint (e.g. https://your-nuxeo.cloud.nuxeo.com/nuxeo),
  #              auth_token (Bearer token) OR username + password (Basic)
  class NuxeoAdapter < Base
    PAGE_SIZE = 100

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      offset = cursor.to_i.zero? ? 0 : cursor.to_i
      # NXQL query for all document assets in the default repository
      nxql   = URI.encode_www_form_component("SELECT * FROM Document WHERE ecm:mixinType = 'Picture' AND ecm:isProxy = 0 ORDER BY dc:created")
      url    = "#{endpoint}/api/v1/query?query=#{nxql}&pageSize=#{limit}&currentPageIndex=#{offset / limit}"

      data   = get_json(url)
      items  = Array(data['entries'] || [])

      files = items.map do |item|
        props = item['properties'] || {}
        {
          identifier:    item['uid'] || item['path'],
          size:          props.dig('file:content', 'length').to_i,
          original_name: props.dig('file:content', 'name') || item['title'],
          metadata: {
            'title'        => props['dc:title'] || item['title'],
            'description'  => props['dc:description'],
            'tags'         => Array(props['dc:subjects']),
            'creator'      => props['dc:creator'],
            'created'      => props['dc:created'],
            'modified'     => props['dc:modified'],
            'content_type' => props.dig('file:content', 'mime-type')
          }.compact
        }
      end

      {
        files:       files,
        next_cursor: (offset + items.size).to_s,
        has_more:    !data['isLastPageAvailable'] || data['isLastPageAvailable'] == false
      }
    end

    def download_and_stream(file_identifier, &block)
      # Nuxeo blob download endpoint
      download_url = "#{endpoint}/api/v1/id/#{file_identifier}/@blob/file:content"
      stream_http_file(download_url, '.bin', &block)
    end

    def test_connection
      get_json("#{endpoint}/api/v1/query?query=SELECT+*+FROM+Document&pageSize=1")
      { success: true, message: "Connected to Nuxeo at #{endpoint}." }
    rescue => e
      { success: false, message: "Nuxeo connection failed: #{e.message}" }
    end

    protected

    def default_headers
      if credentials['username'].present?
        # Basic auth fallback
        require 'base64'
        encoded = Base64.strict_encode64("#{credentials['username']}:#{credentials['password']}")
        {
          'Authorization' => "Basic #{encoded}",
          'Accept'        => 'application/json',
          'Content-Type'  => 'application/json',
          'User-Agent'    => 'CapriDAM-Migrator/1.0'
        }
      else
        super
      end
    end
  end
end

