namespace :couchbase_model do
  desc "Build Elasticsearch Mappings"
  task :es_mapping => :environment do
    CouchbaseModel::ElasticSearch::Mapping.update_mappings
  end

  desc "Delete all the ES data - for new mapping"
  task :es_del_mapping => :environment do 
    CouchbaseModel::ElasticSearch::Mapping.delete_mappings ENV['INDEX'], ENV['TYPE']
  end
  
  desc "Repopulate Elasticsearch"
  task :es_repopulate => :environment do
    CouchbaseModel::ElasticSearch::Mapping.repopulate ENV['ONLY']
  end
end