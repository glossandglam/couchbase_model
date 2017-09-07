class CouchbaseModel
  module Core
    module Saving
  
      TOTAL_SAVE_ATTEMPTS = 5
      
      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods      
        def generate_id(type = nil)
          SecureRandom.hex(20)
        end
      end
      
      def save_only(attribute)
        updated_data = {}
        (attribute.is_a?(Array) ? attribute : [ attribute ]).each {|attr| updated_data[attr] =  _only_changed_attribute(attr) }
        return false unless (saved_data = perform_actual_save(0, updated_data))
        self.class._generate_couchsitter_model(self, saved_data)
        true
      end
      
      def save(options = {})
        now = Time.now
        
        unless options[:skip_filters]
          return false if !self.id && self.class.invoke_action(:before_create, self) === false
          return false if self.class.invoke_action(:before_save, self) === false
        end
        
        return false unless (saved_data = perform_actual_save)
        self.class.invoke_action(:after_save, self) unless options[:skip_filters]
        self.class._generate_couchsitter_model(self, saved_data)
        true
      end
      
      def save!
        save
      end
      
      def set_save_lock!
        @save_lock = true
      end
      
      def release_save_lock!
        @save_lock = false
      end
      
      protected
      
      def perform_actual_save(tries = 0, changed_data = :all)
        return if @save_lock
        
        # Generate the ID now if the ID is not random, so that we can load anything that may already exist
        self.id = generate_id_for_save! unless self.class.is_id_random?
        # Prepare the Data
        data = prep_the_data_for_save changed_data
        begin
          # Set if the ID is set.
          if self.id
            return self.class.couchbase.set(self.key, data, format: :plain) ? data : false
          else
            opts = { format: :plain }
            opts[:ttl] = self.class.ttl if self.class.ttl
            generate_id_for_save!
            return self.class.couchbase.add(self.key, data, opts) ? data : false
          end
        rescue
          return perform_actual_save(tries + 1, changed_data) unless tries < TOTAL_SAVE_ATTEMPTS
        end
        false
      end
      
      def generate_id_for_save!
        self.id = self.respond_to?(:generate_id) ? self.generate_id : self.class.generate_id
      end
      
      # We need to prep the data for save
      # If we are sending in specific data (like from only particular fields), then only update that data
      def prep_the_data_for_save(changed_data)
        data = nil
        if self.id
          unless data
            data = self.class.couchbase.get(self.key, format: :plain, quiet: true)
            data = data ? Oj.load(data, symbol_keys: true) : {}
          end
          
          data.merge!(changed_data == :all ? _only_changed : changed_data)
        else
          data = (changed_data == :all ? data_to_save : changed_data)
        end
        
        CouchbaseModel::Core::Attributes.set_default_values self.class, data
        
        # Perform the OJ Dump
        Oj.dump(data, mode: :compat, time_format: :ruby)
      end
      
      
      # Methods to prepare data for saving
      #####################################
      
      def data_to_save
        out = data.dup
        out.select!{|k,v| self.class.attributes(false)[k] }
        out.each {|attr, value| out[attr] = CouchbaseModel::Core::Attributes.reverse_ensure(self.class.attributes(false)[attr], out, attr) }
        out
      end
      
      def _only_changed
        out, tmp = {}, data.dup
        self.class.attributes(false).each do |n, attr|
          if self.send "#{n}_changed?".to_sym
            out[n] = _only_changed_attribute n, tmp
          end
        end
        out
      end
      
      def _only_changed_attribute(n, out = nil)
        out = data.dup unless out.is_a?(Hash)
        CouchbaseModel::Core::Attributes.reverse_ensure(self.class.attributes(false)[n], out, n)
      end
    end
  end
end
