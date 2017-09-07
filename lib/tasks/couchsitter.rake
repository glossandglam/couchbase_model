namespace :couchsitter do
  module CouchsitterESTask
    def self.put_mapping(es, options, map, indices = nil)
      begin
        es.indices.put_mapping index: options[:index], type: options[:type], body: {
          options[:type] => { properties: map}
        }
      rescue
        return if indices.nil?
        return unless indices.key? options[:index].to_s
        return unless indices[options[:index].to_s].key? 'settings'
        
        es.indices.create index: options[:index], body: { settings: indices[options[:index].to_s]['settings'] }
        put_mapping(es, options, map)
      end
    end
  end

  desc 'Build Elasticsearch Mappings'
  task :es_mapping => :environment do
    models = []
    
    to_check = []
    Dir[Rails.root.join('app', 'models').to_s + "/**/*.rb"].each do |f|
      f.slice!(Rails.root.join('app', 'models').to_s + "/")
      f.slice!(".rb")
      require f unless Module.const_defined?(f.camelize)
      to_check << Module.const_get(f.camelize) if Module.const_defined?(f.camelize)
    end
    
    to_check.each do |item|  
      next unless item.is_a? Module
      next unless item.ancestors.include? CouchbaseModel::ElasticSearch
      models << item
    end
    
    indices = YAML.load_file(Rails.root.to_s + "/config/elasticsearch/indices.yml")
    models.each do |klass|
      next unless klass.respond_to? :elastic_search
      options = klass.elastic_search
      next unless options
      
      map = {}
      
      # Set ES TTL if there is a CB ttl
      map[:_ttl] = { enabled: true, default: "#{klass.ttl}s"} if klass.ttl

      klass.attributes(false).each do |name, attr|
        next unless attr[:elastic_search]
        opts = attr[:elastic_search]
        map[name] = {}
        map[name][:type] = opts[:type] || :string
        if map[name][:type].to_sym == :string
          map[name][:index] = opts[:index] || :not_analyzed
        end
        map[name][:format] = opts[:format] if opts.key? :format
      end
      
      CouchsitterESTask.put_mapping($elasticsearch, options, map, indices)
    end
  end

  desc "Delete all the ES data - for new mapping"
  task :es_del_mapping => :environment do 
    indices = YAML.load_file(Rails.root.to_s + "/config/elasticsearch/indices.yml")
    indices.keys.each do |index|
      begin
        if ENV['INDEX'].nil?
          puts "Deleting #{index}"
          $elasticsearch.indices.delete index: index
        elsif ENV['INDEX'].to_s.strip.eql?(index.to_s.strip)
          if ENV['TYPE'].nil?
            puts "Deleting #{index}"
            $elasticsearch.indices.delete index: index
          else
            puts "Deleting #{index}:#{ENV['TYPE']}"
            $elasticsearch.indicies.delete_mapping index: index, type: ENV['TYPE']
          end
        end
      rescue
      end
    end
  end
  
  desc "Repopulate Elasticsearch"
  task :es_repopulate => :environment do
    $couchbase.save_design_doc({"_id" =>  "_design/more_all", "language" => "javascript", "views" => { "all" => { "map" => "function(doc, meta) { emit(null); }"}}})

    view = $couchbase.design_docs['more_all']
    Dir[Rails.root.join('app', 'models').to_s + "/**/*.rb"].each do |f|
      f.slice!(Rails.root.join('app', 'models').to_s + "/")
      f.slice!(".rb")
      
      next if !ENV['ONLY'].blank? && ENV['ONLY'].to_s != f.camelize.to_s
      cls = Module.const_get f.camelize
      
      next unless cls.respond_to? :elastic_search
      puts cls.name
      k = "#{cls.prefix}:id:"
      list = (view.all(include_docs: true).fetch().map do |c| 
        next unless c.id >= k && c.id <= "#{cls.prefix}:ie"
        m = cls.new
        m.id = c.id[k.size, c.id.size - k.size]
        cls._generate_couchsitter_model m, c.doc.is_a?(Hash) ? c.doc : Oj.load(c.doc)
      end).select{|k| k}
      
      puts list.count
      unless list.empty?
        list.each {|l| l.elasticsearch_update; print "."}
        puts ""
      end
#      CouchbaseModel::ElasticSearch.create_bulk_update(list)
    end
  end
end