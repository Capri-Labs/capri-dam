module CdnAdapters
  class BaseAdapter
    def initialize(credentials)
      @credentials = credentials
    end

    def purge_tag(tag)
      raise NotImplementedError, "Adapters must implement purge_tag"
    end

    def purge_batch(tags, options = {})
      raise NotImplementedError, "Adapters must implement purge_batch"
    end

    def sync_metadata(uuid, json_payload)
      raise NotImplementedError, "Adapters must implement sync_metadata"
    end
  end
end
