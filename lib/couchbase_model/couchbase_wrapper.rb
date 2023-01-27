class CouchbaseModel
  module CouchbaseWrapper 
    def initialize(couchbase)
      @couchbase = couchbase
    end

    def get(key, options = nil)
      results = key.is_a?(Array) ? @couchbase.get_multi(key, options) : @couchbase.get(key, options) 

      process_gotten_item results
    end

    def add(key, item, options = nil)
      @couchbase.insert key, prepare_for_setting(item), options
    end

    def set(key, item, options = nil)
      @couchbase.upsert key, prepare_for_setting(item), options
    end

    def delete(key, options = nil)
      @couchbase.remove key, options
    end

    private

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