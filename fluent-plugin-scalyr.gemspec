$:.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |gem|
  gem.name = "fluent-plugin-scalyr"
  gem.summary = "Scalyr plugin for fluentd"
  gem.description = "Sends log data collected by fluentd to Scalyr (http://www.scalyr.com)"
  gem.homepage = "https://github.com/scalyr/scalyr-fluentd"
  gem.version = File.read("VERSION").strip
  gem.authors = ["Imron Alston"]
  gem.email = "imron@imralsoftware.com"
  gem.has_rdoc = false
  gem.platform = Gem::Platform::RUBY
  gem.files = `git ls-files`.split("\n")
  gem.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.require_paths = ['lib']
  gem.add_dependency "fluentd", [">= 0.10.49", "< 2"]
  gem.add_dependency "yajl-ruby", "~> 1.0"
  gem.add_dependency "fluent-mixin-config-placeholders", ">= 0.3.0"
  gem.add_development_dependency "rake", ">= 0.9.2"
  gem.add_development_dependency "flexmock", ">= 1.2.0"
  gem.add_development_dependency "test-unit", ">= 3.0.8"
end
