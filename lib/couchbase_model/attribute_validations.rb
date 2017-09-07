class CouchbaseModel
  module AttributeValidations
    def self.included(base)
      base.extend(ClassMethods)
      base.before_save :attribute_validations_check
    end
    
    module ClassMethods
    end
    
    # Check to see if the attribute is inside of a collection
    def self.check_collection(model, attribute, options)
      error, keys = :incorrect, false
   
      if options.is_a?(Hash)
        error = options[:error] || :error
        keys = options[:keys] if options.key? :keys
        options = options[:collection]
      end
      
      if options.is_a?(Hash)
        options = keys ? options.keys : options.values
      end
      
      if options.is_a?(Array)
        return false if options.include? model.send(attribute)
      end
      
      error
    end
    
    def errors
      @errors = {} unless @errors.is_a?(Hash)
      @errors
    end

    def attribute_validations_check
      errors.clear
      self.class.attributes(false).each do |attr, attr_options|
        errors[attr] = {}
        attr_options.each do |key, options|
          error = case key
          when :validate_in_collection
            CouchbaseModel::AttributeValidations.check_collection self, attr, options
          end
          
          errors[attr][key] = error if error
        end
        
        # If we don't have any errors in this
        errors.delete(attr) if errors[attr].empty?
      end
    end
  end
end