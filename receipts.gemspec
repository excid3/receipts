# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'receipts/version'

Gem::Specification.new do |spec|
  spec.name          = "receipts"
  spec.version       = Receipts::VERSION
  spec.authors       = ["Chris Oliver"]
  spec.email         = ["excid3@gmail.com"]
  spec.summary       = %q{Receipts for your Rails application that works with any payment provider.}
  spec.description   = %q{Receipts for your Rails application that works with any payment provider.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "pry"

  spec.add_dependency 'prawn', '>= 1.3.0', '< 3.0.0'
  spec.add_dependency 'prawn-table', '~> 0.2.1'
end
