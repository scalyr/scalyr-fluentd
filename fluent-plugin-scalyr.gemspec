# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

Gem::Specification.new do |gem|
  gem.name = "fluent-plugin-scalyr"
  gem.summary = "Scalyr plugin for fluentd"
  gem.description = "Sends log data collected by fluentd to Scalyr (http://www.scalyr.com)"
  gem.homepage = "https://github.com/scalyr/scalyr-fluentd"
  gem.version = File.read("VERSION").strip
  gem.authors = ["Imron Alston"]
  gem.licenses = ["Apache-2.0"]
  gem.email = "imron@scalyr.com"
  gem.platform = Gem::Platform::RUBY
  gem.files = Dir["AUTHORS", "Gemfile", "LICENSE", "README.md", "Rakefile", "VERSION",
                  "fluent-plugin-scalyr.gemspec", "fluent.conf.sample", "lib/**/*", "test/**/*"]
  gem.test_files = Dir.glob("{test,spec,features}/**/*")
  gem.executables = Dir.glob("bin/*").map {|f| File.basename(f) }
  gem.require_paths = ["lib"]
  gem.add_dependency "ffi", "1.9.25"
  gem.add_dependency "fluentd", [">= 0.14.0", "< 2"]
  gem.add_dependency "rbzip2", "0.3.0"
  gem.add_dependency "zlib"
  gem.add_development_dependency "bundler", "~> 1.9"
  gem.add_development_dependency "flexmock", "~> 1.2"
  gem.add_development_dependency "rake", "~> 0.9"
  gem.add_development_dependency "rubocop", "~> 0.4"
  gem.add_development_dependency "test-unit", "~> 3.0"
end
