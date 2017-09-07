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
  include CouchbaseModel::ElasticSearch
  include CouchbaseModel::Indicies
  
  class << self
    def couchbase_connect(opts)
      @@_couchbase = Couchbase.connect opts
    end
    
    def couchbase
      @@_couchbase
    end
    
    def elasticsearch_connect(opts)
      @@_elasticsearch_client = Elasticsearch::Client.new opts
    end
    
    def elasticsearch_client
      @@_elasticsearch_client
    end
  end
end