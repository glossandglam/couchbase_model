class CouchbaseModel
  module Statesman
    def self.included(base)
      base.extend(ClassMethods)
      
      attribute :_statesman_state, private: true
      attribute :_statesman_currently_completed, private: true
    end
    
    module ClassMethods
      @@__statesmen = {}

      def states(keys)
        __setup_statesman
        extra = @@__statesmen[self.name][:states].keys - keys
        @@__statesmen[self.name][:order] = keys + extra
      end
      
      def state(key, state)
        __setup_statesman
        @@__statesmen[self.name][:states][key] = [] unless @@__statesmen[self.name][key].is_a?(Array)
        @@__statesmen[self.name][:states][key] << state
      end
      
      def has_state?(key)
        __setup_statesman
        @@__statesmen[self.name][:states][key] ? true : false
      end
      
      def next_state(key = nil)
        __setup_statesman
        order = @@__statesmen[self.name][:order].empty? ? @@__statesmen[self.name][:states].keys : @@__statesmen[self.name][:order]
        if key
          key = order.index(key)
          key = key ? key + 1 : nil
        else
          key = 0
        end
        key ? order[key] : nil
      end
      
      def state_actions(key)
        __setup_statesman
         @@__statesmen[self.name][:states][key]
      end
      
      def __setup_statesman
        @@__statesmen[self.name] = { states: {}, order: []} unless @@__statesmen[self.name].is_a?(Hash)
      end
    end
      
    def start_statesman! 
      self._statesman_state = self.class.next_state
      run_statesman!
    end
      
    def run_statesman!
      return unless self._statesman_currently_completed.nil?
      self._statesman_currently_completed = []
      self.save_only :_statesman_currently_completed
      
      self.class.state_actions(self._statesman_state).each do |method|
        if respond_to?(method.to_sym)
          send(method.to_sym) 
        else
          self._statesman_currently_completed << method.to_sym
        end
      end
      
      self.save
    end
    
    def jump_to_state!(state)
      return unless self.class.has_state?(state)
      self._statesman_state = state 
      self._statesman_currently_completed = nil
      self.run_statesman!
    end
    
    def statesman_acted!(action)
      self._statesman_currently_completed << action
      if (self._statesman_currently_completed.map{|a| a.to_sym} & self.class.state_actions(self._statesman_state).map{|a| a.to_sym}).count == self.class.state_actions(self._statesman_state).count
        self.jump_to_state! self.class.next_state(self._statesman_state)
      end
    end
  end
end