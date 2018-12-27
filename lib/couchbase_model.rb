require "couchbase"
require "elasticsearch"

require "oj"
require "securerandom"
require "couchbase_model/utilities"

# Require the needed files
Dir[File.dirname(__FILE__) + "/couchbase_model/**/*.rb"].each {|f| require f}

class CouchbaseModel
  include CouchbaseModel::Base
      
  def self.inherited(subclass)
    return unless @to_execute_on_inherited
    @to_execute_on_inherited.each {|block| block.call(self, subclass)}
  end
  
  include CouchbaseModel::Core::Attributes
  include CouchbaseModel::Core::Json
  include CouchbaseModel::Core::Saving
  
  include CouchbaseModel::Core::Filters
  include CouchbaseModel::Core::Calculated
  
  include CouchbaseModel::ElasticSearch::General
  include CouchbaseModel::Indicies
  
  class Init
    class ElasticSearch
      attr_accessor :client
      
      def indexes
        @indexes || {}
      end
      
      def indexes=(idx)
        return unless idx.is_a?(Hash)
        @indexes = CouchbaseModel::Utilities.symbolize idx
      end
    end
    
    attr_accessor :couchbase
    
    def elasticsearch(set_hash = nil)
      @es = ElasticSearch.new unless @es
      
      set_hash.each {|k,v| send("#{k}=".to_sym, v) if respond_to?("#{k}=".to_sym) } if set_hash.is_a?(Hash)
        
      @es
    end
  end
  
  class << self    
    @@_init = nil
    @@_cb = nil
    @@_es_client = nil
    
    def init
      @@_init = CouchbaseModel::Init.new unless @@_init
      @@_init
    end
    
    def metrics
      @metrics.is_a?(Hash) ? @metrics : (@metrics = {})
    end
    
    def record_metric(metric)
      time = Time.now
      res = yield
      
      time = (Time.now - time).to_f
      metrics[metric] = { avg: 0, cnt: 0 } unless metrics[metric].is_a?(Hash)
      metrics[metric][:avg] = ((metrics[metric][:avg] * metrics[metric][:cnt]) + time) / (metrics[metric][:cnt] + 1)
      metrics[metric][:cnt] += 1
      
      res
    end
    
    def couchbase
      @@_cb = Couchbase.connect(init.couchbase) unless @@_cb
      @@_cb    
    end
    
    def elasticsearch_client
      @@_es_client = Elasticsearch::Client.new(init.elasticsearch.client) unless @@_es_client
      @@_es_client
    end
    
    def all_couchbase_models
      models = []
      
      # If we are using Rails, we can require all the models and figure it out
      if defined?(Rails)
        Dir[Rails.root.join('app', 'models').to_s + "/**/*.rb"].each do |f|
          f.slice!(Rails.root.join('app', 'models').to_s + "/")
          f.slice!(".rb")
          
          class_name = f.clone
          class_name.slice!("concerns/")
          class_name = class_name.camelize
          
          require f unless Module.const_defined?(class_name)
          model = Module.const_get(class_name) if Module.const_defined?(class_name)
          next unless model
          next unless model.ancestors.include?(CouchbaseModel)
          models << model
        end
      end
      models
    end
  end
end