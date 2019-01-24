class CouchbaseModel
  module Core
    module Filters
      def self.included(base)
        base.extend(ClassMethods)
        
        base.to_execute_on_inherited do |parent, child|
          parent._actions.keys.each do |action|
            child._actions[action] = parent._actions[action].clone
          end
        end
        
        base.create_filter_methods ACTIONS
      end

      ACTIONS = [:after_load, :before_save, :after_save, :all_saved, :after_destroy, :before_create, :attribute_updated]
      
      module ClassMethods
        def _actions
          @actions = {} unless @actions
          @actions
        end
        
        def metaclass
          class << self; self; end
        end
        
        def create_filter_methods(actions)
          (actions.is_a?(Array) ? actions : [actions]).each do |action|
            next if _actions[action]
            _actions[action] = [] 
            metaclass.instance_eval do
              define_method(action) do |function, options = {}|      
                _actions[action] << { method: function, options: options}
              end
            end
          end
        end
        
        def invoke_action(action, object, options = nil, invoke_options = {})
          return unless _actions[action]
          object.clear_errors_from_filter!(action) 
          _actions[action].uniq.each do |data|
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
      
      def errors_from_filter(filter)
        filter = :default unless filter
        errors_from_all_filters[filter] = {} unless errors_from_all_filters[filter]
        errors_from_all_filters[filter]
      end
      
      def errors_from_all_filters
        @errors_from_filters = {} unless @errors_from_filters
        @errors_from_filters
      end
      
      def errors_from_filters
        return {} if errors_from_all_filters.empty?
        errors_from_all_filters.values.reduce Hash.new, :merge
      end
      
      def clear_errors_from_filters!
        @errors_from_filters.clear if @errors_from_filters
      end
      
      def clear_errors_from_filter!(filter)
        errors_from_filter(filter).clear
      end
      
      protected
      
      def add_filter_error(message, error = :error)
        errors_from_filter(_currently_active_filter)[error] = message
        false
      end
      
      def invoke_action!(action)
        self.class.invoke_action(action, self)
      end
      
      def _currently_active_filter
        @_currently_active_filter || :default
      end
      
      def _set_currently_active_fllter(action)
        @_currently_active_filter = action
      end
    end
  end
end