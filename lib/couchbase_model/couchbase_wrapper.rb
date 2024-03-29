class CouchbaseModel
  class CouchbaseWrapper 
    def initialize(couchbase)
      @couchbase = couchbase
    end

    def get(key, options = {})
      key.is_a?(Array) ? get_multiple(key, options) : get_single(key, options)
    end

    def add(key, item, options = {})
      opts = Couchbase::Options::Insert.new(**options.slice(:timeout))
      opts.expiry = options[:ttl] if options[:ttl]

      @couchbase.insert key, prepare_for_setting(item, key), opts
    end

    def set(key, item, options = {})
      opts = Couchbase::Options::Upsert.new(**options.slice(:timeout))
      opts.expiry = options[:ttl] if options[:ttl]

      @couchbase.upsert key, prepare_for_setting(item, key), opts
    end

    def delete(key, options = {})
      key.is_a?(Array) ? remove_multiple(key, options) : remove_single(key, options)
    end

    private

    def get_single(key, options = {})
      opts = Couchbase::Options::Get.new(**options.slice(:timeout))
      document = begin
        @couchbase.get(key, opts) 
      rescue Couchbase::Error::DocumentNotFound 
        nil
      end

      process_gotten_item document
    end

    def get_multiple(keys, options = {})
      opts = Couchbase::Options::GetMulti.new(**options.slice(:timeout))
      process_gotten_item @couchbase.get_multi(keys, opts)
    end

    def remove_single(key, options = {})
      opts = Couchbase::Options::Remove.new(**options.slice(:timeout))
      @couchbase.remove key, opts
    end

    def remove_multiple(keys, options = {})
      opts = Couchbase::Options::RemoveMulti.new(**options.slice(:timeout))
      @couchbase.remove_multi keys, opts
    end

    def process_gotten_item(item)
      return item.map {|child| process_gotten_item child } if item.is_a?(Array)

      item = item&.content
      return item unless item
      return item if item.is_a?(Array)
      return item unless item.key?('__val')

      item['__val']
    end

    def prepare_for_setting(item, key = nil)
      return item if item.is_a?(Hash)
      return item.map {|child| prepare_for_setting(child)} if item.is_a?(Array)

      { '__val' => item, '__key' => key }
    end
  end
end