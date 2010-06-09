Gem::Specification.new do |s|
  s.name = %q{rack_direct}
  s.version = "0.1.1"
  s.date = %q{2010-06-09}
  s.authors = ["Brian Sharon"]
  s.email = %q{brian@floatplane.us}
  s.summary = %q{RackDirect allows you to easily perform integration tests with your ActiveResource services, by bringing them up in a standalone process and communicating with them via stdio instead of over a socket.}
  s.homepage = %q{http://floatplane.us/}
  s.description = <<-EOF
RackDirect allows you to easily perform integration tests with your ActiveResource services, by bringing them up in a standalone process and communicating with them via stdio instead of over a socket.
EOF
  s.files = [ "README", "lib/rack_direct.rb"]
end
