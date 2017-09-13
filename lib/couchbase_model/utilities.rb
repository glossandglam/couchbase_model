class CouchbaseModel
  module Utilities
    class << self
      def _check_multiple(options, v, extra = {})
        if options[:multiple]
          v = [v] unless v.nil? || v.is_a?(Array)
          out = (v || []).map do |vv|
            yield(vv)
          end
          return extra[:no_nulls] ? out.select{|s| not s.nil?} : out
        end
        
        yield(v)
      end
      
      def symbolize(hash)
        if hash.is_a? Array
          return hash.map{|v| symbolize v}
        elsif not hash.is_a? Hash
          return hash
        end
        
        new_hash = {}
        hash.each do |k,v|
          if v.is_a? Hash
            new_hash[to_key k] = symbolize(v)
          elsif v.is_a? Array
            new_hash[to_key k] = v.map{|v| symbolize(v)}
          else
            new_hash[to_key k] = v
          end
        end
        new_hash
      end
    
      def to_key(k)
        k.to_s.to_sym
      end
    end
  end
end