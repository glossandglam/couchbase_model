class CouchbaseModel
  module Core
    module Attributes
      def self.included(base)
        base.extend(ClassMethods)
        base.include CouchbaseModel::Core::Encrypt
      end
      
      module ClassMethods
        @@_attributes = {}
        
        def attributes(keys = true)
          @@_attributes[self.name] = {} unless @@_attributes.key? self.name
          keys ? @@_attributes[self.name].keys : @@_attributes[self.name]
        end
        
        def attribute(attribute, options = {})
          attribute = attribute.to_sym
          @@_attributes[self.name] = {} unless @@_attributes.key? self.name
          unless @@_attributes[self.name].key?(attribute)
            @@_attributes[self.name][attribute] = options
            
            define_method(attribute) {|func_opts = {}| CouchbaseModel::Core::Attributes.get self, options || {}, attribute, func_opts } unless instance_methods.include?(attribute) && !CouchbaseModel.instance_methods.include?(attribute) 
            define_method("#{attribute}=".to_sym) {|v, func_opts={}| CouchbaseModel::Core::Attributes.set self, options || {}, attribute, v, func_opts }
            
            define_method("#{attribute}_changed?".to_sym) { not self.data[attribute].eql?(self.original_value attribute) }
            define_method("#{attribute}_original".to_sym) { self.original_value attribute}
            if options[:multiple]
              define_method("add_to_#{attribute}") {|item, func_opts={}| CouchbaseModel::Core::Attributes.add_to self, attribute, item, options[:multiple] != :list, func_opts }
              define_method("remove_from_#{attribute}") {|item, func_opts={}| CouchbaseModel::Core::Attributes.remove_from self, attribute, item, func_opts }
              define_method("clear_#{attribute}") { CouchbaseModel::Core::Attributes.clear self, attribute }
              define_method("in_#{attribute}?") {|item, func_opts={}| CouchbaseModel::Core::Attributes.in self, attribute, item, func_opts }
            end
          end
          @@_attributes[self.name][attribute]
        end
      end
      
      def self.get(model, options, attribute, func_opts)         
        if options[:multiple]               
          model.data[attribute] = model.data[attribute].nil? ? [] : [ model.data[attribute] ] unless model.data[attribute].is_a?(Array)
          model.data[attribute] = (options[:multiple] == :list ? model.data[attribute] : model.data[attribute].uniq).map {|k| func_opts[:id].nil? && options[:class] && !k.is_a?(CouchbaseModel) ? options[:class].load(k, model.__references) : k}
        else
          model.data[attribute] = options[:class].load(model.data[attribute], model.__references) if func_opts[:id].nil? && options[:class] && !model.data[attribute].is_a?(CouchbaseModel)
        end
        
        # Going to have to check this type of ensurance
        CouchbaseModel::Core::Attributes.ensure_type(options, model, attribute)
        
        CouchbaseModel::Utilities._check_multiple(options, model.data[attribute], no_nulls: true) do |v|
          v = v[:data] if v.is_a?(Hash) && v[:data] && options[:ttl]
          v = v.respond_to?(:id) && func_opts[:id] ? v.id : v
          v
        end
      end
      
      def self.add_to(model, attribute, item, unique = true, opts = {})  
        options = model.class.attributes(false)[attribute]
        
        item = CouchbaseModel::Core::Encrypt.hash_attribute(item, options[:encrypt], opts) if options[:encrypt]
        model.data[attribute] = [] unless model.data[attribute]
        model.data[attribute] << item 
        model.data[attribute].uniq! if unique 
        item
      end
      
      def self.remove_from(model, attribute, item, opts = {})
        options = model.class.attributes(false)[attribute]
        model.data[attribute] = [] unless model.data[attribute]
        
        modal.data[attribute].delete(CouchbaseModel::Core::Encrypt.hash_attribute(item, options[:encrypt], opts)) if options[:encrypt]
        model.data[attribute].delete(item.id) if item.is_a?(CouchbaseModel)
        model.data[attribute].delete item 
      end
      
      def self.clear(model, attribute)
        model.data[attribute] = [] 
      end
      
      def self.in(model, attribute, item, opts = {})
        options = model.class.attributes(false)[attribute]
        model.data[attribute.to_sym] = [] unless model.data[attribute.to_sym]
        
        item = CouchbaseModel::Core::Encrypt.hash_attribute(item, options[:encrypt], opts) if options[:encrypt]
        item = item.is_a?(CouchbaseModel) ? item.id : item
        model.data[attribute.to_sym].map{|m| m.is_a?(CouchbaseModel) ? m.id : m}.include?(item) 
      end
      
      def self.set(model, options, attribute, value, opts = {})    
        options = model.class.attributes(false)[attribute]
        model.data[attribute] = CouchbaseModel::Utilities._check_multiple(options, value) do |v|
          # Perform Encryption? 
          v = CouchbaseModel::Core::Encrypt.hash_attribute(v, options[:encrypt], opts) if options[:encrypt]
          
          v = { data: v, expires: (Time.now.utc + options[:ttl]) } if options[:ttl]
          v
        end
      end
        
      def self.ensure_type(options, model, k)
        model.data[k] = CouchbaseModel::Utilities._check_multiple(options, model.data[k], no_nulls: true) {|v| v } if options[:nil] === false
        
        _check_transience(options, model.data, k, true) if options[:ttl]
        
        case options[:type]
        when :date
          _dateify(options, model, Date, k, model.data[k])
        when :datetime
          _dateify(options, model, Time, k, model.data[k])
        when :hash
          _objectify(options, model, k)
        end
      end

      def self.reverse_ensure(options, hash, k)
        return nil unless options
        
        _check_transience(options, hash, k, true) if options[:ttl]
        
        return _unclassify(options, hash, k) if options[:class]
        case options[:type]
        when :date
          _undatify(options, hash, Date, k, "%F")
        when :datetime
          _undatify(options, hash, Time, k, "%FT%T%:z")
        else
          hash[k]
        end
      end
      
      def self._check_transience(options, hash, k, show_full = true)
        hash[k] = CouchbaseModel::Utilities._check_multiple(options, hash[k]) do |v|
          v.is_a?(Hash) && v[:expires] && v[:expires].to_i > Time.now.utc.to_i ? v : nil
        end
      end
      
      def self._unclassify(options, hash, k)
        hash[k] = CouchbaseModel::Utilities._check_multiple(options, hash[k]) do |v|
          v.respond_to?(:id) ? v.id : v
        end
      end
      
      def self._objectify(options, model, k)
        model.data[k] = CouchbaseModel::Utilities._check_multiple(options, model.data[k]) do |v|
          v.is_a?(Hash) ? v : {}
        end
      end
      
      def self._dateify(options, model, dateType, k, v)
        model.data[k] = CouchbaseModel::Utilities._check_multiple(options, model.data[k]) do |i|
          if i.is_a?(dateType)
            i
          else
            begin
              dateType.parse i
            rescue
              nil
            end
          end
        end 
      end   
      
      def self._undatify(options, hash, dateType, k, strftime)
        hash[k] = CouchbaseModel::Utilities._check_multiple(options, hash[k]) do |v|
          v.is_a?(dateType) ? v.strftime(strftime) : v
        end
      end
      
      protected
      
      def self.set_default_values(cls, data = nil)  
        return unless data.is_a?(Hash)
        # Set Default Values on NIL elements
        cls.attributes(false).each {|attr, opts| data[attr] = opts[:default] if data[attr].nil? && opts[:default] }
      end
    end
  end
end