# frozen_string_literal: true

require_relative "lib/izar/version"

Gem::Specification.new do |spec|
  spec.name = "izar"
  spec.version = Izar::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Pure Ruby Git staging workspace"
  spec.description = "A safe, thin TUI and CLI layer over Thuban and Porrima for reviewing and staging Git changes."
  spec.homepage = "https://github.com/noxdea/izar"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = "https://github.com/noxdea/izar"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[Gemfile .gitignore .rspec spec/ .github/])
    end
  end
  spec.bindir = "bin"
  spec.executables = ["izar"]
  spec.require_paths = ["lib"]

  spec.add_dependency "antares", "~> 0.2"
  spec.add_dependency "kochab", "~> 0.2"
  spec.add_dependency "porrima", "~> 0.2"
  spec.add_dependency "spica", "~> 0.1"
  spec.add_dependency "thuban", "~> 0.6"
  spec.add_dependency "zaniah", ">= 0.6.0", "< 0.7"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
