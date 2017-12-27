require "couchbase"
require "elasticsearch"

require "oj"
require "securerandom"
require "couchbase_model/utilities"

# Require the needed files
Dir[File.dirname(__FILE__) + "/couchbase_model/**/*.rb"].each {|f| require f}

class CouchbaseModel
  include CouchbaseModel::Base
  include CouchbaseModel::Core::Attributes
  include CouchbaseModel::Core::Json
  include CouchbaseModel::Core::Saving
  
  include CouchbaseModel::Filters
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
    def init
      @@_init = CouchbaseModel::Init.new unless @@_init
      @@_init
    end
    
    def couchbase
      @@_cb = Couchbase.connect(init.couchbase) unless @@_cb
      @@_cb    
    end
    
    def elasticsearch_client
      @@_es_client = Elasticsearch::Client.new(init.elasticsearch.client) unless @@_es_client
      Rails.logger.info @@_es_client.inspect
      @@_es_client
    end
    
    def all_couchbase_models
      models = []
      Dir[Rails.root.join('app', 'models').to_s + "/**/*.rb"].each do |f|
        f.slice!(Rails.root.join('app', 'models').to_s + "/")
        f.slice!(".rb")
        require f unless Module.const_defined?(f.camelize)
        model = Module.const_get(f.camelize) if Module.const_defined?(f.camelize)
        next unless model.is_a?(CouchbaseModel)
        models << model
      end
      models
    end
  end
end