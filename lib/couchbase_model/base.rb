class CouchbaseModel
  module Base
  
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods    
      def to_execute_on_inherited(&block)
        return unless self.eql?(CouchbaseModel)
        @to_execute_on_inherited = [] unless @to_execute_on_inherited
        @to_execute_on_inherited << block
      end
    
      def find(object = nil)
        return nil unless object
        load object
      end
      
      def key(id)
        "#{prefix}:id:#{id}"
      end
      
      def exists?(id)
        begin
          k = key(id)
          self.couchbase.add k, nil
          self.couchbase.delete k
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
      
      def is_id_random?(value = nil)
        return (@_is_id_random.nil? ? true : @_is_id_random) if value.nil?
        @_is_id_random = value
      end
      
      def _generate_couchsitter_model(model, data, references = {})
        model.data, model.__references = (data.is_a?(Hash) ? data : Oj.load(data, symbol_keys: true)), references
        
        # Set the default values
        CouchbaseModel::Core::Attributes.set_default_values model.class, model.data
        
        invoke_action(:after_load, model)
        model._first_data = model.data.deep_dup
        model
      end
      
      # The internal "loading" functionality to load and generate a single
      # model from the database
      #
      # @return [CouchbaseModel]
      def load(id, references = {})
        return references[key(id)] if references[key(id)]
        result = self.couchbase.get(key(id), format: :plain, quiet: true)
        return nil unless result
        model = new
        model.id = id
        _generate_couchsitter_model(model, result, references || {})
      end
      
      # This function will load multiple ids and return an array
      #
      # It is used by the elasticsearch's "load" functionality to reduce the number of DB calls
      #
      # @return [Array]
      def load_many(ids, references = {})
        found, missing = {}, []
        
        # This is basically splitting the ids into those it has found and those it is missing
        ids.each {|id| k = key(id); references[k] ? (found[id] = references[k]) : (missing << id) }
        
        unless missing.empty?
          results = self.couchbase.get(missing.map{|id| key(id)}, format: :plain, quiet: true)
          
          missing.each_index do |i|
            next unless results[i]
            model = new
            model.id = missing[i]
            found[missing[i]] = _generate_couchsitter_model(model, results[i], references)
          end if results.is_a?(Array)
        end
        
        ids.select{|id| found.key?(id)}.map{|id| found[id]}
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
      not self.data[attribute].eql? self.original_value(attribute)
    end
    
    def all_changed_attributes
      (self.data.keys + @_firstdata.keys).uniq.select{|k| value_changed?(k)}
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
