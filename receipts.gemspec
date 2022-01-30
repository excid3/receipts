# frozen_string_literal: true

require_relative "lib/receipts/version"

Gem::Specification.new do |spec|
  spec.name = "receipts"
  spec.version = Receipts::VERSION
  spec.authors = ["Chris Oliver"]
  spec.email = ["excid3@gmail.com"]

  spec.summary = "Receipts for your Rails application that works with any payment provider."
  spec.description = "Receipts for your Rails application that works with any payment provider."
  spec.homepage = "https://github.com/excid3/receipts"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/excid3/receipts/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "prawn", ">= 1.3.0", "< 3.0.0"
  spec.add_dependency "prawn-table", "~> 0.2.1"
end
