class CouchbaseModel
  module RedisStore
    def self.included(base)
      base.extend(ClassMethods)
      base.after_save :redisstore_update
      base.after_save :redisstore_global
    end
    
    module ClassMethods
      def lookup_redis(attribute, value)
      end
      
      def redis_index_key(attribute, value)
        "#{self.prefix}:indicies:#{attribute}:#{value}"
      end
    end
    
    def redis_lookup(attribute)
      $redis.smembers redis_key(attribute)
    end
    
    def redis_key(attribute)
      "#{self.key}:#{attribute}"
    end
    
    def redisstore_update
      self.class.attributes(false).each do |attribute, hash|
        next unless hash[:redis]
        next unless self.value_changed? attribute
        key = redis_key attribute
        if self.data[attribute].nil? || self.data[attribute].empty?
          $redis.del key
          next
        end
        
        $redis.pipelined do |r|
          r.srem(key, self.original_value(attribute) - self.data[attribute]) unless (self.original_value(attribute) - self.data[attribute]).empty?
          r.sadd(key, self.data[attribute] - self.original_value(attribute)) unless (self.data[attribute] - self.original_value(attribute)).empty?
        end
      end
    end
    
    def redisstore_global
      self.class.attributes(false).each do |attribute, hash|
        next unless hash[:global_redis]
        next unless self.value_changed? attribute
        val = self.data[attribute].is_a?(Array) ? self.data[attribute] : [self.data[attribute]]
        oldval = self.original_value(attribute).is_a?(Array) ? self.original_value(attribute) : [self.original_value(attribute)]
        keys = val.map{|v| self.class.redis_index_key(attribute, v)}
        orig_keys = oldval.map{|v| self.class.redis_index_key(attribute, v)}
        
        $redis.pipelined do |r|
          orig_keys.each do |k|
            next unless k
            r.srem(k, self.id)
          end
          keys.each do |k|
            next unless k
            r.sadd(k, self.id)
          end
        end
      end
    
    end
  end
end