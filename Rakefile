# frozen_string_literal: true

require "bundler"
Bundler::GemHelper.install_tasks

require "rake/testtask"

Rake::TestTask.new(:test) do |test|
  test.libs << "lib" << "test"
  test.test_files = FileList["test/test_*.rb"]
  test.verbose = true
  test.options = "--verbose=verbose"
end

task default: [:build]
