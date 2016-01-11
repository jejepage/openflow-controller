require_relative 'lib/openflow-controller/version'

Gem::Specification.new do |s|
  s.name         = 'openflow-controller'
  s.version      = OpenFlow::Controller::VERSION
  s.authors      = ['Jérémy Pagé']
  s.email        = ['contact@jeremypage.me']

  s.summary      = 'OpenFlow Controller'
  s.description  = 'An OpenFlow Controller.'

  s.files        = `git ls-files lib`.split("\n")
  s.test_files   = `git ls-files spec`.split("\n")
  s.executables  = `git ls-files bin`.split("\n").map { |f| File.basename(f) }
  s.require_path = 'lib'

  s.homepage     = 'https://github.com/jejepage/openflow-controller'
  s.license      = 'MIT'

  s.add_runtime_dependency 'openflow-protocol', '0.1.6'
  s.add_runtime_dependency 'colored', '~> 1.2'
  s.add_runtime_dependency 'cri', '~> 2.7'
  s.add_development_dependency 'rspec', '~> 3.2'
end
