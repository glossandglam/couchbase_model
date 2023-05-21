class CouchbaseModel
  module ElasticSearch
    module General
      def self.included(base)
        base.extend(ClassMethods)
        base.after_save :elasticsearch_update
        base.after_destroy :elasticsearch_destroy
      end
      
      # Amount of times we should retry the update
      MAX_CONFLICT_TRIES = 3
      
      module ClassMethods
        def elastic_search(options = nil)
          unless @_elasticsearch or !options.is_a?(Hash)
            @_elasticsearch = {}.merge options
          end
          @_elasticsearch
        end
        
        def search_wildcard(attribute, value, options = {})
          es_attr = CouchbaseModel::ElasticSearch::General.elasticsearch_attributes(self)
          value = CouchbaseModel::ElasticSearch::General.format_fields(value, es_attr[attribute])
          query = []
          query << {wildcard: { attribute => { value: (options[:both_sides] ? "*" : "")+"#{value}*"}}}
          
          if options[:where].is_a? Hash
            filters = CouchbaseModel::ElasticSearch::General.elasticsearch_filters(options[:where], es_attr)
            query += filters
          end
          
          query = { bool: { must: query }}
          options[:count] ? __count_with_query(query) : __search_with_query(query, options)  
        end
        
        def search_by(attribute, value, options = {})
          es_attr = CouchbaseModel::ElasticSearch::General.elasticsearch_attributes(self)
          options[:sort] = attribute unless options[:sort]
          value = CouchbaseModel::ElasticSearch::General.format_fields(value,  es_attr[attribute])
          filter = value.is_a?(Array) ? { terms: { attribute => value }} : { term: { attribute => value }}
          __search_with_query({ bool: { must: filter }}, options)
        end
        
        def search_all(options = {})
          es_attr = CouchbaseModel::ElasticSearch::General.elasticsearch_attributes(self)
          
          query = []
      
          query += (options[:match] || options[:multi_match]).map do |key, value|
            { match: { key => value }}
          end if (options[:match] || options[:multi_match]).is_a?(Hash)
          
          if options[:where].is_a?(Hash)
            query += CouchbaseModel::ElasticSearch::General.elasticsearch_filters(options[:where], es_attr)
          end
          
          query = query.empty? ? { match_all: {} } : { bool: { must: query }}
          options[:count] ? __count_with_query(query) : __search_with_query(query, options)                  
        end
        
        def __count_with_query(query)
          results = self.elasticsearch_client.count index: elastic_search[:index],
                                body: { query: query }
          results["count"].to_i
        end
        
        def __search_with_query(query, options) 
          options[:offset] = options[:offset] || 0
          options[:size] = options.key?(:size) ? options[:size] : 20
          body = {
                  from: options[:offset],
                  query: query,
                  size: options[:size] || 300
                }
          
          if options[:sort].is_a?(Hash)
            body[:sort] = options[:sort]
          else
            body[:sort] = { options[:sort] => options[:order] || "asc" } if options[:sort]
          end
          
          if const_defined?("Rails")
            Rails.logger.info "ES Query -----------------------"
            Rails.logger.info body.to_json
            Rails.logger.info "--------------------------------"
          end

          results = self.elasticsearch_client.search index: elastic_search[:index],
                                body: body
          
          ids = results["hits"]["hits"].map{|item| item["_id"]}
          options[:load] ? load_many(ids) : ids
        end
        
        def elasticsearch_destroy_all(ids)
          begin
            (id.is_a?(Array) ? ids : [ids]).each do |id|
              self.elasticsearch_client.delete index: elastic_search[:index], id: self.id
            end
          rescue
          end
        end
      
        def elasticsearch_create_bulk_update(list, do_change = false)
          out = []
          list.each do |model|
            out << { update: { _id: model.id, _index: model.class.elastic_search[:index]}}
            out << CouchbaseModel::ElasticSearch::General.format_update(model, update: true, change: do_change)
            
            if out.count > 500
              self.elasticsearch_client.bulk(body: out)
              out.clear
            end
          end
          
          self.elasticsearch_client.bulk(body: out) unless out.empty?
        end
      end
      
      def self.ensure_date(value)
        return value if value.is_a?(Date) || value.is_a?(Time)
        return Time.parse(value) if value.is_a?(String)
        return Time.at(value).to_datetime if value.is_a?(Numeric)
        nil
      end
      
      def self.format_fields(value, options)
        options = {} unless options.is_a?(Hash)
        case options[:type]
        when :boolean
          return value ? true : false
        when :hash
          return CouchbaseModel::ElasticSearch::General.hasher(value, options[:structure]) || nil
        end
      
        case options[:format]
        when :date_time_no_millis
          d = CouchbaseModel::ElasticSearch::General.ensure_date value
          return d ? d.strftime("%FT%T%:z") : nil
        when :date
          d = CouchbaseModel::ElasticSearch::General.ensure_date value
          return d ? d.strftime("%F") : nil
        end
        
        if value.is_a?(CouchbaseModel)
          return value.id
        end
        
        value = value.to_s.downcase if options[:case_insensitive] && options[:type] == :string    
        value.is_a?(String) ? value.strip : value
      end
      
      def self.elasticsearch_hasher(model, options)
        data = model.data
        out = {}
        options.each do |attribute, opts|
          if opts[:value_func] && model.respond_to?(opts[:value_func].to_sym)
            out[attribute] = model.send opts[:value_func].to_sym
            next
          end
          if data[attribute].is_a?(Array)
            out[attribute] = []
            data[attribute].each do |d|
              out[attribute] << CouchbaseModel::ElasticSearch::General.format_fields(d, opts)
            end
          else
            out[attribute] = CouchbaseModel::ElasticSearch::General.format_fields data[attribute], opts
          end
        end
        out
      end
      
      def self.elasticsearch_filters(query, opts = {})
        filters = []
        query.each do |n,v|
          case n
          when :not
            filters << { bool: { must_not: elasticsearch_filters(v, opts)}}
          when :or 
            filters << { bool: { should: v.map{|vv| elasticsearch_filters(vv, opts)}}}
          when :and
            filters << { bool: { must: v.map{|vv|elasticsearch_filters(vv, opts)}}}
          else
            if v.is_a? Hash
              v.each do |nn, vv|
                case nn.to_sym
                when :range
                  rg = {}
                  vv.each do |ty, val|
                    if [:gt, :lt, :gte, :lte].include? ty.to_sym
                      rg[ty] = CouchbaseModel::ElasticSearch::General.format_fields(val, opts[n.to_sym])
                    else
                      rg[ty] = val
                    end
                  end
                  filters << { range: { n => rg }}
                when :exists
                  out = { missing: { field: n }}
                  out = { not: out } if vv
                  filters << out
                when :distance
                  next unless vv.is_a?(Hash)
                  out = { geo_distance: { 
                    distance: vv[:distance],
                    n => {
                      lat: vv[:lat] || vv[:latitude],
                      lon: vv[:lon] || vv[:longitude]
                    }
                  }}
                  out[:geo_distance][:distance_type] = vv[:type] if vv[:type]
                  filters << out
                end
              end
            elsif v.is_a? Array
              if v.none?{|vv| vv.is_a?(Hash)}
                filters << { terms: { n => v.map{|vv| CouchbaseModel::ElasticSearch::General.format_fields(vv, opts[n.to_sym])}}}
              else
                filters << self.elasticsearch_filters({or: v.map{|vv| {n => vv}}}, opts[n.to_sym])
              end
            else
              filters << { term: { n => CouchbaseModel::ElasticSearch::General.format_fields(v, opts[n.to_sym])}}
            end
          end
        end
        
        filters
      end
      
      def self.elasticsearch_attributes(cls)
        attrs = {}
        cls.attributes(false).each do |a, options|
          next unless options[:elastic_search]
          attrs[a] = options[:elastic_search]
        end
        attrs
      end
      
      def elasticsearch_update
        return unless self.class.elastic_search
        tries = 0
        
        # So here's the thing. Sometimes, there will be conflicts, since Elasticsearch takes 1 second to do an update. The thing is that our Couchbase data is VERY VERY fast and it's unlikely that the 
        # Later data will not be absolutely correct, so we're just going to just try the update again.
        while tries < MAX_CONFLICT_TRIES
          begin
            self.class.elasticsearch_client.index index: self.class.elastic_search[:index], id: self.id,
              body: CouchbaseModel::ElasticSearch::General.format_update(self)
            break
          rescue Exception => e
            tries += 1
          end
        end
      end
      
      def self.format_update(model, options = {})
        es_attr = CouchbaseModel::ElasticSearch::General.elasticsearch_attributes(model.class) if options[:es_attr].nil?
      
        upsert = elasticsearch_hasher(model, es_attr)
        insert = {}
        upsert.keys.each do |k|
          insert[k] = upsert[k] unless upsert[k].nil?
          insert[k].select!{|v| not v.nil? } if insert[k].is_a?(Array)
        end
        
        out = {}
        
        if options[:update]
          if options[:change]
            change = upsert.deep_dup
            model.class.attributes(false).each do |attribute, options|
              change.delete(attribute) unless model.value_changed?(attribute) || (es_attr[attribute] && es_attr[attribute][:value_func])
            end
          end
          out[:doc] = options[:change] ? change : upsert 
          out[:upsert] = upsert
        else
          out = upsert
        end
        
        out
      end
      
      def elasticsearch_destroy
        begin
          self.class.elasticsearch_client.delete index: self.class.elastic_search[:index], id: self.id
        rescue
        end
      end
    end
  end
end