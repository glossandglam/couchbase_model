if defined?(Rails)
  class CouchbaseModel
    module RailsExtensions
      if defined?(Rails::Railtie)
        class Railtie < Rails::Railtie
          rake_tasks do 
            Dir[File.join(File.dirname(__FILE__), "../tasks/*.rake")].each {|f| import f}
          end
        end
      end
    end
  end
end