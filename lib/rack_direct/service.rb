require 'rack_direct/guid'
require 'open3'
require 'tmpdir'
require 'rack_direct/active_resource'

RACK_DIRECT_ALIAS = 'rack-direct'

module RackDirect

  class Service

    class << self
      attr_accessor :verbose_logging
    end

    @@services = {}
    def self.start name, path
      unless @@services[name]

        tmppath = generate_rackup_file

        # TODO: check path to make sure a Rails app exists there
        print "Starting service rack-direct://#{name}..."
        cmd = "cd #{path} && rake db:test:prepare && rackup --server #{RACK_DIRECT_ALIAS} #{tmppath} 2>&1"
        # puts cmd
        @@services[name] = IO.popen cmd, "w+"
        puts "done."

        at_exit do
          RackDirect::Service.stop name
          File.unlink tmppath
        end
      end
      "rack-direct://#{name}"
    end

    def self.send_request name, rack_request_env

      if @@services[name]

        rack_request_env["direct_request.unique_id"] = Guid.new.to_s

        @@services[name].puts rack_request_env.to_json
        @@services[name].puts ""

        response = ""
        in_response = false
        while true
          line = @@services[name].gets
          if line.strip == "BEGIN #{rack_request_env["direct_request.unique_id"]}"
            in_response = true
            next
          elsif line.strip == "END #{rack_request_env["direct_request.unique_id"]}"
            break
          elsif in_response
            response += line
          else
            puts "rack-direct://#{name}: #{line.strip}" if self.verbose_logging
          end
        end
        # puts "Final response: #{response}"
        response
      end

    end

    def self.stop name
      if @@services[name]
        print "Stopping service rack-direct://#{name}..."
        @@services[name].puts "EXIT"
        @@services[name].puts ""
        @@services[name] = nil
        Process.waitall
        puts "done."
      end
    end

    private

    def self.generate_rackup_file
      rackup_file_contents = <<-EOF
$: << '~/src/rack-direct/lib'
require 'rack_direct/direct_handler'
Rack::Handler.register('#{RACK_DIRECT_ALIAS}', 'RackDirect::DirectHandler')
# puts "RackDirect::DirectHandler registered"

require "config/environment"
use Rails::Rack::LogTailer
use Rails::Rack::Static
run ActionController::Dispatcher.new
EOF
      tmppath = nil
      Tempfile.open("rack_direct") { |x| tmppath = x.path + ".ru" }
      tmpfile = File.open tmppath, "w+"
      tmpfile.write rackup_file_contents
      tmpfile.close

      tmppath
    end

  end

end
