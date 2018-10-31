Gem::Specification.new do |s|
  s.name        = 'couchbase_model'
  s.version     = '0.0.1'
  s.date        = '2017-06-28'
  s.summary     = "Couchbase + Elasticsearch"
  s.description = ""
  s.authors     = ["Jeremy Linder"]
  s.email       = 'jeremy@nomibeauty.com'
  s.files       = ["lib/couchbase_model.rb"]
  s.license     = 'MIT'
  
  s.add_runtime_dependency 'activesupport'
  
  s.add_runtime_dependency 'couchbase', '~> 2.0'
  s.add_runtime_dependency 'elasticsearch'
  
  s.add_runtime_dependency 'oj'
end