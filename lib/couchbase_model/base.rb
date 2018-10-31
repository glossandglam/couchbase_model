class CouchbaseModel
  module Base
  
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      def find(object = nil)
        return nil unless object
        load object
      end
      
      def key(id)
        "#{prefix}:id:#{id}"
      end
      
      def exists?(id)
        begin
          self.couchbase.add key(id), nil
          self.couchbase.delete key(id)
          false
        rescue
          true
        end
      end
      
      def prefix(prefix = nil)
        @prefix = prefix if prefix
        @prefix
      end
      
      def ttl(seconds = nil)
        @ttl = seconds unless seconds.nil?
        @ttl
      end
      
      def key(id)
        "#{prefix}:id:#{id}"
      end
      
      def classname
        self.name
      end
      
      @@_is_id_random = {}
      
      def is_id_random?(value = nil)
        return (@@_is_id_random.key?(self.name) ? @@_is_id_random[self.name] : true) if value.nil?
        @@_is_id_random[self.name] = value
      end
      
      def _generate_couchsitter_model(model, data, references = {})
        model.data, model.__references = (data.is_a?(Hash) ? data : Oj.load(data, symbol_keys: true)), references
        
        # Set the default values
        CouchbaseModel::Core::Attributes.set_default_values model.class, model.data
        
        model._first_data = model.data.deep_dup
        invoke_action(:after_load, model)
        model
      end
      
      def load(id, references = {})
        return references[key(id)] if references[key(id)]
        result = self.couchbase.get(key(id), format: :plain, quiet: true)
        return nil unless result
        model = new
        model.id = id
        _generate_couchsitter_model(model, result, references)
      end
      
      def load_many(ids, references = {})
        missing = ids.select{|id| not references.key?(key(id))}
        
        unless missing.empty?
          results = self.couchbase.get(missing.map{|id| key(id)}, format: :plain, quiet: true)
          
          missing.each_index do |i|
            id = missing[i]
            res = results[i]
            next unless res
            model = new
            model.id = id
            references[key(id)] = _generate_couchsitter_model(model, res, references)
          end unless results.is_a?(Array)
        end
        
        ids.map{|id| references[key(id)]}
      end
      
      def attribute_value_toload(model, k, value) 
        options = attributes(false)[k]
        if options[:class]
          klass = options[:class]
          if klass
            model.data[k] = klass.load(value)
            return
          end
        end
        
        case options[:type]
        when :date
          model[k] = value.is_a?(Date) ? value : DateTime.parse(value)
        else
        end      
      end
    end
  
    attr_accessor :__references
     
    def initialize(attributes = {})
      @_firstdata = attributes.deep_dup
      self.class.attributes(false).each do |attribute, options|
        if options[:multiple]
          self.data[attribute] = [] 
          @_firstdata[attribute] = []
        end
      end
    end
    
    def key
      "#{self.class.prefix}:id:#{self.id}"
    end
    
    def fresh_copy
      self.class.find self.id
    end
    
    def destroy
      self.class.invoke_action(:after_destroy, self) if self.class.couchbase.delete self.key
    end
    
    def id
      @id
    end
    
    def data
      @data = {} unless @data
      @data
    end
    
    def eql?(obj)
      return false unless obj.is_a?(CouchbaseModel)
      key.eql? obj.key
    end
    
    def id=(i)
      @id = i
    end
    
    def data=(d)
      @data = d
    end
    
    def original_value(attribute)
      @_firstdata[attribute]
    end
    
    def value_changed?(attribute)
      not self.data[attribute].eql? @_firstdata[attribute]
    end
    
    def _first_data=(data)
      @_firstdata = data
    end
    
    def _set_first_data_attr(attribute, value)
      @_firstdata[attribute] = value
    end
    
    def ==(obj)
      if (obj.is_a?(self.class))
        return obj.id == self.id
      end
      false
      
    end
    
    def __references
      @references = {} unless @references
      @references
    end
    
    protected
    
    def first_data
      @_firstdata
    end
  end
end
