$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "rack_direct/version"

def run_cmd cmd
  puts cmd
  system cmd
end

GEM_FILE = "rack_direct-#{RackDirect::VERSION}.gem"

task :clean do
  run_cmd "rm -f #{GEM_FILE}"
end

task :build => :clean do
  run_cmd "gem build rack-direct.gemspec"
end

task :release => :build do
  run_cmd "gem push #{GEM_FILE}"
end
