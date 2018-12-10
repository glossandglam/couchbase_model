class CouchbaseModel
  module Core
    module Json
      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods        
        def json_attributes
          @_custom_json_attributes = {} unless @_custom_json_attributes
          @_custom_json_attributes
        end
        
        def json_attribute(attribute, options = {}, &block)
          attribute = attribute.to_sym
          json_attributes[attribute] = { options: options || {}, method: options[:method] || block }
        end
      end
      
      def to_json(options = {})
        Oj.dump(as_json(options), mode: :compat, time_format: :ruby)
      end
      
      # Basic AS_JSON
      #
      # There are three types of attributes that this method will build for a CouchbaseModel
      #
      # 1. The regular saved CouchbaseModel attributes
      # 2. The transient calculations for this appointment
      # 2. Any defined JSON attributes
      #
      # It is important to note that while (1) and (2) will be cached as they normally would
      # (whether from the first calculation or save), (3) will be freshly calculated every time
      def as_json(options = {})  
      
        #Setup the references
        has_refs = options[:references].is_a?(Hash)
        options[:references] = {} unless has_refs
        
        key = "#{self.class.name}:#{id}"
        return options[:references][key] if options[:references][key].is_a?(Hash)
        
        # For Couchbase models, use as_json
        publicize = options[:publicize].is_a?(Hash) ? options[:publicize] : {}
        only_fields = CouchbaseModel::Core::Json.parse_json_only options[:only]
        
        export = {id: self.id}
        
        # Fiirst, let's compile the attributes
        self.class.attributes(false).each do |k, attr|
          next unless CouchbaseModel::Core::Json.include_field_in_json?(k.to_sym, attr, publicize, only_fields, options)
          export[k] = export_for_json k, data[k], attr, (only_fields ? options.merge(only: only_fields[k]) : options)
        end
        
        # Now, we'll compile the calculations
        self.class._calculated_fields.each do |k, attr|
          next unless CouchbaseModel::Core::Json.include_field_in_json?(k.to_sym, attr, publicize, only_fields, options)
          export[k] = calculated_field_value(k)
        end
        
        # Finally, we'll build the custom JSON attributes
        self.class.json_attributes.each do |k, attr_opts|
          # If we aren't including this JSON attribute, go to the next one
          next unless CouchbaseModel::Core::Json.include_field_in_json?(k.to_sym, attr_opts[:options], publicize, only_fields, options)          
          method = attr_opts[:method]
          
          # If the method is a proc, then just do that proc
          if method.is_a?(Proc)
            export[k] = method.call(self, options, export)
            next
          end
          
          # We can also allow the method to be a symbol, for easier use
          method = method.to_sym
          
          next unless respond_to?(method, true)

          # We'll call it in different ways, dependent on the arity of the method
          # There can be 0-2 attributes on the method, with the first attribute being
          # the options sent to the json and the second option being the already exported
          # JSON object itself
          export[k] = case self.method(method).arity
          when 0
            send(method)
          when 1
            send(method, options)
          when -1
            send(method, options)
          when 2
            send(method, options, export)
          when -2
            send(method, options, export)
          end
        end
        
        # If we were send a references object already, add this item to it. Otherwise, create a references object
        has_refs ? (options[:references][key] = export) : (export[:_references] = options[:references])
        
        export
      end
      
      
      # These methods export the Array / Objects to JSON format
      def export_for_json(k, v, attrs, options)
        CouchbaseModel::Utilities._check_multiple(attrs, v, no_nulls: attrs[:nil] === false) do |vv|
          export_json_type k, vv, attrs, options
        end
      end
      
      def export_json_type(k, v, attrs, options)  
        return CouchbaseModel::Core::Json.couchsitter_object(k, v, attrs, options) if attrs[:class]
        return CouchbaseModel::Core::Json.date_object(v, attrs[:type]) if [:date, :datetime].include?(attrs[:type])     
        val = attrs[:multiple] ? v : self.send(k)
        if val.is_a?(CouchbaseModel)
          key = "#{val.class.name}:#{val.id}"
          options[:references][key] = val.as_json(options)
          key
        else 
          val.as_json(options)
        end
      end
      
      protected
      
      # Prepare and Output a Couchsitter Object into References
      def self.couchsitter_object(obj_key, object, attributes = {}, options = {})
        return nil unless object
        return nil unless attributes[:class]
        id = object.is_a?(CouchbaseModel) ? object.id : object
        
        # If we've requested to not return the whole object, then just return the ID
        return id unless options[:full_model].nil? || options[:full_model]
        return id if options[:include].is_a?(Array) && !options[:include].include?(obj_key.to_s)
        
        key = "#{attributes[:class].name}:#{id}"
        return key if options[:references][key]
        
        # Temporary Placeholder
        options[:references][key] = true
        mdl = object.is_a?(CouchbaseModel) ? object : attributes[:class].find(object)
        out = mdl.is_a?(CouchbaseModel) ? mdl.as_json(options) : nil
        options[:references][key] = out
        options[:api_version].to_i > 0 ? key : out
      end
      
      
      # Prepare and Output a Date Object
      def self.date_object(value, type)
        return nil unless value
        begin
          case type
          when :date
            (value.is_a?(Date) ? value : Date.parse(value)).strftime("%F")
          when :datetime
            (value.is_a?(Time) ? value : Time.parse(value)).strftime("%FT%T")
          else
            value
          end
        rescue
          value
        end
      end
      
      def self.parse_json_only(attribute_list)
        return nil unless attribute_list.is_a?(Array)
      
        out = {}
        
        # We'll make this list into one of a hash where the keys are the attributes, pointing to the sub attributes
        attribute_list.each do |attr|
          breakdown = attr.to_s.split(".")
          key = breakdown.shift.to_sym
          if out[key]
            out[key] << breakdown.join(".")
          else
            out[key] = (breakdown.empty? ? true : [breakdown.join(".")])
          end
        end
        
        out
      end
      
      
      def self.include_field_in_json?(field, field_options, publicities, only_fields, json_options)
        # If this is a private field that is not publicized, then nope
        return false unless publicities[:_all] || publicities[field] || !field_options[:private]
        
        if only_fields
          # If we have set only fields, and this field is not one of them, nevermind
          return false unless only_fields[field]
        else
          # If a field is set as visibility = false, then it can only be viewed as an only field
          return false if field_options[:visibility] === false
        end
        
        true
      end
    end
  end
end