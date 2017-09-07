class CouchbaseModel
  module Indicies
    def self.included(base)
      base.extend(ClassMethods)
      base.before_save :indicies_check_index
      base.after_save :indicies_create_index
      base.after_destroy :indicies_destroy_from_index
    end
    
    module ClassMethods
      def lookup_attribute(attribute, v, full_model = false)
        value = CouchbaseModel::Indicies.index_value(v)
        begin
          id = $couchbase.get indicies_index_key(attribute, value)
          return id unless full_model
          id.is_a?(Array) ? id.map{|i| find(i)} : find(id)
        rescue
          nil
        end
      end
      
      def attr_exists?(attribute, v, internal_id = nil)
        value = CouchbaseModel::Indicies.index_value(v)
        key = indicies_index_key(attribute, value)
        
        unless internal_id
          begin
            internal_id = self.couchbase.get key
          rescue
            return false
          end
          return false unless internal_id
        end
        
        begin
          self.couchbase.add internal_id, 1
          self.couchbase.delete internal_id
        rescue
          self.couchbase.delete indicies_index_key(attribute, value)
          return false
        end
        true
      end
      
      def indicies_index_key(attribute, v)
        value = CouchbaseModel::Indicies.index_value(v)
        "#{self.prefix}:indicies:#{attribute}:#{value}"
      end
    end
    
    def self.index_value(value, options = {})
      if value.is_a?(CouchbaseModel)
        value.id
      else
        value.to_s.strip.downcase
      end
    end
    
    def indicies_check_index
      self.class.attributes(false).each do |attribute, hash|
        next unless hash
        next unless hash[:index]
        value = CouchbaseModel::Core::Attributes.reverse_ensure(hash, self.data, attribute)
        next if value.nil?
        case hash[:index]
        when :unique
          key = self.class.indicies_index_key(attribute, value)
          begin
            myid = self.class.couchbase.get key
          rescue
            next
          end
          
          # If we are switching from non-unique to unique but can still make it unique
          if myid.is_a?(Array)
            return false if myid.length > 1
            return false unless myid.first.eql?(self.id) || !self.class.exists?(myid.first)
            self.class.couchbase.delete self.class.indicies_index_key(attribute, value)
            next
          end
          
          return false unless !myid || myid.eql?(self.id) || !self.class.exists?(myid)
        end
      end
    end
    
    def indicies_create_index
      self.class.attributes(false).each do |attribute, hash|
        next unless hash
        next unless hash[:index]
        next unless value_changed?(attribute)
        type = hash[:index].is_a?(Hash) ? hash[:index][:type] : hash[:index]
        value = CouchbaseModel::Core::Attributes.reverse_ensure(hash, self.data, attribute)
        original_value = CouchbaseModel::Core::Attributes.reverse_ensure(hash, self.first_data, attribute)
        
        opts = {}
        opts[:ttl] = self.class.ttl if self.class.ttl
        case type
        when :unique
          if value
            begin
              self.class.couchbase.add(self.class.indicies_index_key(attribute, value), self.id, opts) unless value.nil?
            rescue
              return false
            end
          end
          if original_value
            begin
              self.class.couchbase.delete self.class.indicies_index_key(attribute, original_value)
            rescue
            end
          end
        else
          next if value.nil?
          current = []
          begin 
            current = $couchbase.get self.class.indicies_index_key(attribute, value)
          rescue
          end
          current = [current] unless current.is_a?(Array)
          current << self.id
          
          self.class.couchbase.set self.class.indicies_index_key(attribute, value), current, opts
        end
      end
    end
    
    def indicies_destroy_from_index
      self.class.attributes(false).each do |attribute, hash|
        next unless hash
        next unless hash[:index]
        
        value = CouchbaseModel::Core::Attributes.reverse_ensure(hash, self.data, attribute)
        next if value.nil?
        
        case hash[:index]
        when :unique
          begin
            self.class.couchbase.delete self.class.indicies_index_key(attribute, value)
          rescue
          end
        else
          current = []
          begin 
            current = self.class.couchbase.get self.class.indicies_index_key(attribute, value)
          rescue
          end
          current = [current] unless current.is_a?(Array)
          current.delete self.id
          
          self.class.couchbase.set self.class.indicies_index_key(attribute, value), current
        end
      end
    end
  end
end