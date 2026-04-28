module StorageAdapters
  class BaseAdapter
    def initialize(config = {})
      @config = config
    end

    def store(file, path)
      raise NotImplementedError, "Subclasses must implement the store method"
    end

    def delete(path)
      raise NotImplementedError, "Subclasses must implement the delete method"
    end

    def url(path)
      raise NotImplementedError, "Subclasses must implement the url method"
    end
  end
end