# frozen_string_literal: true

require_relative 'lib/undertow/version'

Gem::Specification.new do |spec|
  spec.name    = 'undertow'
  spec.version = Undertow::VERSION
  spec.authors = ['Nathan Allen']
  spec.summary = 'Buffered, dependency-aware change propagation for ActiveRecord models'

  spec.required_ruby_version = '>= 3.0'

  spec.files = Dir['lib/**/*.rb'] + ['undertow.gemspec']

  spec.add_dependency 'activerecord',  '>= 7.0'
  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'activejob',     '>= 7.0'
  spec.add_dependency 'redis',         '>= 4.0'
end
