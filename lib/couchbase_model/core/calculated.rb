class CouchbaseModel
  module Core
    # Calculate fields are fields that are calculated based on other information
    # inside the data model.
    #
    # They *could* be just calculated on the fly, but by setting up a calculated field
    # in this manner, we trade save performance & size for read performance. This should
    # make the objects faster to load and is very useful for frequently-required items
    #
    # It also allows items to be automatically updated without adding a whole number of
    # extra filters
  
    module Calculated
    
      def self.included(base)
        base.extend(ClassMethods)
        
        base.before_save :refresh_calculated_fields
        base.attribute_updated :recalculate_attached_calculated_fields
      end
      
      module ClassMethods
        @@_calculated_fields = {}
        
        # Dependencies are fields that, when they change, cause a change in one or more
        # of the calculations.
        #
        # So that we reduce the amount of introspection, we require the user to note which fields
        # are accessed / used as dependencies.
        #
        # Without any dependencies, a calculation will never occur
        @@_calculated_field_dependencies = {}
      
        def calculated_field(name, dependencies = [], options = {}, &block)
          name = name.to_sym
          return if _calculated_fields[name]
          
          flattened_dependencies = __flatten_calculated_dependencies dependencies
          
          # Save the dependencies as well as the calculation on top of the sent options
          _calculated_fields[name] = options.merge( dependencies: flattened_dependencies, calculation: block )
          
          # Build the dependencies
          _build_calculated_dependencies name, flattened_dependencies
          
          # And, now that we know the dependencies for this field, we can resolve any fields that are dependent on this one
          _resolve_calculated_dependencies name, flattened_dependencies
          
          # Finally, let's generate the calculation's method 
          define_method(name) { self.calculated_field_value(name) }
        end
        
        # A fast method for looking up the calculated fields on "this" model
        def _calculated_fields
          @@_calculated_fields[self.name] = {} unless @@_calculated_fields[self.name]
          @@_calculated_fields[self.name]
        end
        
        # These are lists of calculations that are dependent on particular attributes
        def _calculated_field_dependencies
          @@_calculated_field_dependencies[self.name] = {} unless @@_calculated_field_dependencies[self.name]
          @@_calculated_field_dependencies[self.name]
        end
        
        private
        
        # We need to keep track of all the fields that this one depends on
        def _build_calculated_dependencies(name, dependencies = [])
          # First, let's flatten the dependency list
          dependencies = __flatten_calculated_dependencies dependencies

          # Now, we'll add the dependencies
          dependencies.each do |dependency|            
            # Otherwise, we need to add this field to the dependcy
            _calculated_field_dependencies[dependency] = [] unless _calculated_field_dependencies[dependency]
            _calculated_field_dependencies[dependency] << name
          end
        end
        
        # It is very possible that a whole bunch of fields are dependent on this one.
        # Moving forward, that will be taken care of by the build, but we need to resolve any fields
        # That might have already been sent as dependent on this one
        def _resolve_calculated_dependencies(name, dependencies)
          (_calculated_field_dependencies[name] || []).each do |dependent|
            dependencies.each do |dependency|
              _calculated_field_dependencies[dependency] << dependent
            end
          end
          
          _calculated_field_dependencies.delete name
        end
        
        
        # This function will recursively find a single, flattened, list of all the dependencies
        # That themselves have no dependencies
        def __flatten_calculated_dependencies(dependencies, dependency_list = [], fields_checked = [])
          (dependencies - fields_checked).each do |dependency|
             fields_checked << dependency
          
            sub_dependencies = _calculated_field_dependencies[dependency]
            # If a dependency itself has no dependencies, then it can be just added
            unless sub_dependencies
              dependency_list << dependency
              next
            end
            
            __flatten_calculated_dependencies sub_dependencies, dependency_list, fields_checked
          end
          
          dependency_list
        end
      
      end
      
      protected
      
      def calculated_field_value(name)
        self.data.key?(name) ? self.data[name] : self.recalculate_calculated_field(name) 
      end
        
      def recalculate_calculated_field(name)
        name = name.to_sym
        self.data[name] = self.class._calculated_fields[name][:calculation].call(self)
      end
      
      def clear_all_calculated_fields
        self.class._calculated_fields.each {|k| self.data.delete k}
      end
      
      def refresh_calculated_fields
        # Gather all the calculations that require updating by checking the updated attributes against the 
        # calculations that depend on them
        calculations_requiring_change = self.all_changed_attributes.map { |attribute| self.class._calculated_field_dependencies[attribute.to_sym] || [] }.flatten.uniq        
        calculations_requiring_change.each {|calculation| recalculate_calculated_field calculation }
      end
      
      def recalculate_attached_calculated_fields (name)
        (self.class._calculated_field_dependencies[name] || []).each {|name| recalculate_calculated_field name}
      end
    end
  end
end