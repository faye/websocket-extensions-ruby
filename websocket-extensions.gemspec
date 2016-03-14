Gem::Specification.new do |s|
  s.name              = 'websocket-extensions'
  s.version           = '0.1.2'
  s.summary           = 'Generic extension manager for WebSocket connections'
  s.author            = 'James Coglan'
  s.email             = 'jcoglan@gmail.com'
  s.homepage          = 'http://github.com/faye/websocket-extensions-ruby'
  s.license           = 'MIT'

  s.extra_rdoc_files  = %w[README.md]
  s.rdoc_options      = %w[--main README.md --markup markdown]
  s.require_paths     = %w[lib]

  s.files = %w[README.md LICENSE.md CHANGELOG.md] + Dir.glob('lib/**/*.rb')

  s.add_development_dependency 'rspec'
end
