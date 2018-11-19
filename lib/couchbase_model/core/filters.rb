class CouchbaseModel
  module Core
    module Filters
      def self.included(base)
        base.extend(ClassMethods)
        base.create_filter_methods ACTIONS
      end

      ACTIONS = [:after_load, :before_save, :after_save, :all_saved, :after_destroy, :before_create, :attribute_updated]
      
      module ClassMethods
        @@_actions = {}
        
        def metaclass
          class << self; self; end
        end
        
        def create_filter_methods(actions)
          (actions.is_a?(Array) ? actions : [actions]).each do |action|
            @@_actions[action] = {}
            metaclass.instance_eval do
              define_method(action) do |function, options = {}|
                @@_actions[action][self.name] = [] unless @@_actions[action][self.name]
                @@_actions[action][self.name] << { method: function, options: options}
              end
            end
          end
        end
        
        def invoke_action(action, object, options = nil)
          return unless @@_actions[action]
          object.clear_errors_from_filters!
          self.ancestors.each do |cls|
            if @@_actions[action][cls.name]
              @@_actions[action][cls.name].uniq.each do |data|
                if data[:method].is_a?(Array)
                  next unless data[:method].first.is_a?(Object)
                  next unless data[:method].first.respond_to?(data[:method].last)
                  options.nil? ? data[:method].first.send(data[:method].last, object) : data[:method].first.send(data[:method].last, object, options)
                else
                  return false if (options.nil? ? object.send(data[:method]) : object.send(data[:method], options)) === false
                end
              end
            end
          end
        end
      end
      
      def errors_from_filters
        @errors_from_filters = {} unless @errors_from_filters
        @errors_from_filters
      end
      
      def clear_errors_from_filters!
        @errors_from_filters.clear if @errors_from_filters
      end
      
      protected
      
      def add_filter_error(message, error = :error)
        errors_from_filters[error] = message
        false
      end
      
      def invoke_action!(action)
        self.class.invoke_action(action, self)
      end
    end
  end
end