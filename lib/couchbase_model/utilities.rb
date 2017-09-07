class CouchbaseModel
  module Utilities
    def self._check_multiple(options, v, extra = {})
      if options[:multiple]
        v = [v] unless v.nil? || v.is_a?(Array)
        out = (v || []).map do |vv|
          yield(vv)
        end
        return extra[:no_nulls] ? out.select{|s| not s.nil?} : out
      end
      
      yield(v)
    end
  end
end