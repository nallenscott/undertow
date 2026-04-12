# frozen_string_literal: true

require_relative 'lib/undertow/version'

Gem::Specification.new do |spec|
  spec.name     = 'undertow'
  spec.version  = Undertow::VERSION
  spec.authors  = ['Nathan Allen']
  spec.email    = ['hello@nallenscott.com']
  spec.summary  = 'Buffered, dependency-aware change propagation for ActiveRecord models'
  spec.homepage = 'https://github.com/nallenscott/undertow'
  spec.license  = 'MIT'

  spec.metadata = {
    'source_code_uri' => 'https://github.com/nallenscott/undertow',
    'changelog_uri'   => 'https://github.com/nallenscott/undertow/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/nallenscott/undertow/issues'
  }

  spec.required_ruby_version = '>= 3.0'

  spec.files = Dir['lib/**/*.rb'] + ['undertow.gemspec']

  spec.add_dependency 'activerecord',  '>= 7.0'
  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'activejob',     '>= 7.0'
  spec.add_dependency 'redis',         '>= 4.0'
end
