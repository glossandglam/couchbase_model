class CouchbaseModel
  module ElasticSearch
    module Mapping
      class << self
        # This function will update all the mappings
        #
        # Using the attributes for all the couchbase models, it will create the proper mappings and 
        # update the bound elastic search instance with those mappings
        def update_mappings
          all_elasticsearch_models.each do |klass|
            options = klass.elastic_search
            puts options.inspect
            
            next unless options
            
            map = {}
            map[:_ttl] = { enabled: true, default: "#{klass.ttl}s"} if klass.ttl # TTL
            
            # Build up the attributes
            klass.attributes(false).each do |name, attr|
              next unless attr[:elastic_search]
              
              map[name] = {}
              map[name][:type] = attr[:type] || :string
              map[name][:index] = attr[:index] || :not_analyzed if map[name][:type].to_sym == :string
              map[name][:format] = attr[:format] if attr.key? :format
            end
            
            puts options.inspect
            puts map.inspect
            
            put_mapping options[:index], map
          end
        end
    
        # This function will delete elasticsearch mappings
        #
        # Deleting a mapping will delete all the information contained in that mapping
        # Sometimes, when there was a mistake made, we need to delete and rebuild the mapping.
        # You can use the index and type insertions to pinpoint the index and/or mapping you want
        # to remove
        def delete_mappings(index = nil, type = nil)        
          CouchbaseModel.init.elasticsearch.indexes.each do |idx, index_options|            
            next unless index.nil? || idx == index.to_sym
            
            begin
              if type && idx == index.to_sym
                CouchbaseModel.elasticsearch_client.indicies.delete_mapping index: index, type: type
                return 
              end
              
              CouchbaseModel.elasticsearch_client.indicies.delete index: idx
            rescue
            end
          end
        end
  
        def repopulate(only = nil)
          all_elasticsearch_models.each do |cls|
            next if only && only.to_s != cls.name.to_s
            
            k = "#{cls.prefix}:id:"
            end_k = "#{cls.prefix}:ie"
            
            list = every_single_document
            
            puts cls
            puts list.count
            list.each do |c|
              next unless c.id >= k && c.id <= end_k
              m = cls.new
              m.id = c.id[k.size, c.id.size - k.size]
              item = cls._generate_couchsitter_model m, c.doc.is_a?(Hash) ? c.doc : Oj.load(c.doc)
              next unless item
              
              item.elasticsearch_update
            end
          end
        end
    
        protected
    
        # This function puts the generated mapping into the index / type
        #
        # If the index does not exist, it builds it according to the index attributes provided
        # to the couchbase model object in an initializer
        def put_mapping(index, map, inside = false)
          begin
            CouchbaseModel.elasticsearch_client.indices.put_mapping index: index, body: {
              properties: map
            }
          rescue
            return if inside
            create_index index
            put_mapping(index, map, true)
          end
        end
        
        # This function creates an index with the data provided the CouchbaseModel 
        def create_index(idx)
          indices = CouchbaseModel.init.elasticsearch.indexes
          return unless indices
          index = indices[idx]
          return unless index
          settings = index[:settings]
          return unless settings
          
          begin
            CouchbaseModel.elasticsearch_client.indices.create index: idx, body: { settings: settings }
          rescue
          end
        end
        
        def all_elasticsearch_models
          CouchbaseModel.all_couchbase_models.select{|m| m.ancestors.include?(CouchbaseModel::ElasticSearch::General)}
        end
        
        # Get every single document in all of couchbase
        def every_single_document
          begin
            CouchbaseModel.couchbase.save_design_doc({"_id" =>  "_design/all", "language" => "javascript", "views" => { "all" => { "map" => "function(doc, meta) { emit(null); }"}}})
            CouchbaseModel.couchbase.design_docs['all'].all(include_docs: true)
          rescue
            []
          end
        end
      end
    end
  end
end