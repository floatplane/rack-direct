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

    def self.log name, msg
      if self.verbose_logging
        msg = msg.gsub(/^/, "#{name}> ")
        puts msg
      end
    end

    @@services = {}
    def self.start path, options = {}

      name = options[:name] || File.split(path).last

      unless @@services[name]

        tmppath = generate_rackup_file name, options[:env]

        # TODO: check path to make sure a Rails app exists there
        self.log name, "starting service via rack_direct..."
        cmd = "cd #{path} && rake db:test:prepare && rackup --server #{RACK_DIRECT_ALIAS} #{tmppath} 2>&1"
        self.log name, cmd
        @@services[name] = IO.popen cmd, "w+"
        self.log name, "service started"

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
            self.log name, "#{line.strip}"
          end
        end
        # self.log name, "Final response: #{response}"
        response
      end

    end

    def self.stop name
      if @@services[name]
        self.log name, "stopping service..."
        @@services[name].puts "EXIT"
        @@services[name].puts ""
        @@services[name] = nil
        Process.waitall
        self.log name, "service stopped."
      end
    end

    private

    def self.generate_rackup_file name, environment
      rackup_file_contents = <<-EOF
require 'rack_direct/direct_handler'
Rack::Handler.register('#{RACK_DIRECT_ALIAS}', 'RackDirect::DirectHandler')
# puts "RackDirect::DirectHandler registered"
EOF

      if environment && environment.is_a?(Hash)
        rackup_file_contents += "# Passed in environment:\n"
        environment.each_pair do |k,v|
          rackup_file_contents += "ENV[#{k}] = #{v}\n"
        end
      end

      rackup_file_contents += <<-EOF
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

      self.log name, "Created rackup file #{tmppath}"

      tmppath
    end

  end

end
