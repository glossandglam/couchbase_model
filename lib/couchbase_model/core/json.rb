class CouchbaseModel
  module Core
    module Json
      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods
      end
      
      def to_json(options = {})
        Oj.dump(as_json(options), mode: :compat, time_format: :ruby)
      end
      
      # Basic AS_JSON
      def as_json(options = {})  
        #Setup the references
        has_refs = options[:references].is_a?(Hash)
        options[:references] = {} unless has_refs
        
        key = "#{self.class.name}:#{id}"
        return options[:references][key] if options[:references][key].is_a?(Hash)
        
        options[:references][key] = true 
        
        # For Couchbase models, use as_json
        publicize = options[:publicize].is_a?(Hash) ? options[:publicize] : {}
        
        export = {id: self.id}
        # Filter out private items
        self.class.attributes(false).select{|k, attrs| publicize[:_all] || publicize[k.to_sym] || !attrs[:private]}.each do |k,attrs|      
          # Display if not private
          export[k] = export_for_json k, data[k], attrs, options
        end
        
        if has_refs
          options[:references][key] = export
        else
          export[:_references] = options[:references]
        end
        
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
    end
  end
end