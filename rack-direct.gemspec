Gem::Specification.new do |s|
  s.name = %q{rack_direct}
  s.version = "0.1.5"
  s.date = %q{2010-06-09}
  s.authors = ["Brian Sharon"]
  s.email = %q{brian@floatplane.us}
  s.summary = %q{RackDirect allows you to easily perform integration tests between multiple Rails websites, by launching your ActiveResource services in a standalone process and communicating with them via stdio instead of over a socket.}
  s.homepage = %q{http://floatplane.us/}
  s.description = <<-EOF
RackDirect allows you to easily perform integration tests between multiple Rails websites, by launching your ActiveResource services in a standalone process and communicating with them via stdio instead of over a socket.
EOF
  require 'rake'
  s.files = FileList['README', 'lib/**/*.rb', 'bin/*', '[A-Z]*', 'test/**/*'].to_a
end
