class CouchbaseModel
  class CouchbaseWrapper 
    def initialize(couchbase)
      @couchbase = couchbase
    end

    def get(key, options = {})
      key.is_a?(Array) ? get_multiple(key, options) : get_single(key, options)
    end

    def add(key, item, options = {})
      opts = Couchbase::Options::Insert.new
      opts.expiry = options[:ttl] if options[:ttl]

      @couchbase.insert key, prepare_for_setting(item), opts
    end

    def set(key, item, options = {})
      opts = Couchbase::Options::Upsert.new
      opts.expiry = options[:ttl] if options[:ttl]

      @couchbase.upsert key, prepare_for_setting(item), opts
    end

    def delete(key, options = {})
      key.is_a?(Array) ? remove_multiple(key, options) : remove_single(key, options)
    end

    private

    def get_single(key, options = {})
      opts = Couchbase::Options::Get.new
      process_gotten_item @couchbase.get(key, opts)
    end

    def get_multiple(keys, options = {})
      opts = Couchbase::Options::GetMulti.new
      process_gotten_item @couchbase.get_multi(key, opts)
    end

    def remove_single(key, options = {})
      opts = Couchbase::Options::Remove.new
      @couchbase.remove key, opts
    end

    def remove_multiple(keys, options = {})
      opts = Couchbase::Options::RemoveMulti.new
      @couchbase.remove_multi key, opts
    end

    def process_gotten_item(item)
      return item.map {|child| process_gotten_item child } if item.is_a?(Array)

      item = item&.content
      return item unless item
      return item if item.is_a?(Array)
      return item unless item.key?("__val")

      item["__val"]
    end

    def prepare_for_setting(item)
      return item if item.is_a?(Hash)
      return item.map {|child| prepare_for_setting(child)} if item.is_a?(Array)

      { "__val" => item }
    end
  end
end