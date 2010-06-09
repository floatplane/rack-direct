require 'rack_direct/direct_handler'
RACK_DIRECT_ALIAS = 'rack-direct'
Rack::Handler.register(RACK_DIRECT_ALIAS, 'RackDirect::DirectHandler')

puts "RackDirect::DirectHandler registered"

require 'rack'
require 'active_resource'
require 'open3'
require 'rack_direct/guid'
require 'tmpdir'

# TODO: 
# break into library
# gem-ify it
# support multiple rack processes with named URLs
# support URL scheme, like "rack-direct://blah" or something 
# when required, run an initializer that plugs into ActiveResource
# ActiveResource hook can override Connection.request and look for special urls
# generate rackup file dynamically in a temp directory
# support option to nuke/not nuke the testdb

# Maybe the crazy URL could point to the file system:
# rack-direct://~/src/.... and then boot the thing if it's not live?
# but then how do you separate the path?

module RackDirect

  class DirectConnection < ActiveResource::Connection
  end

  class DirectResponse < Rack::MockResponse

    include Net::HTTPHeader

    def initialize(status, headers, body, errors=StringIO.new(""))
      super(status, headers, body, errors)
      # Set up @header to make methods in Net::HTTPHeader work
      @header = {}
      @headers.each do |k,v|
        @header[k.downcase] = [v]
      end
    end

    def code
      self.status.to_s
    end

    def message
      if Net::HTTPResponse::CODE_TO_OBJ[self.code]
        Net::HTTPResponse::CODE_TO_OBJ[self.code].to_s.match(/Net::HTTP(.*)/).captures[0].underscore.humanize.titleize
      else
        case self.code
        when /^2/
          'OK'
        when /^4/
          'Not Found'
        when /^3/
          'Redirect'
        else
          'Error'
        end
      end
    end
  end

  class ActiveResource::Connection
    def request(method, path, *arguments)
      raise "TODO: passthrough http" unless site.scheme == "rack-direct"
      # puts "#{method.to_s.upcase} #{site.scheme}://#{site.host}:#{site.port}#{path}" if logger
      result = nil

      headers = arguments.last
      body = arguments.first if arguments.length > 1

      payload = {
        # We can't pass through a site.scheme of 'rack-direct' because
        # the Rack instance on the receiving end will freak out.
        "uri" => "http://#{site.host}:#{site.port}#{path}",
        "method" => method.to_s.upcase,
        "body" => body,
        "CONTENT_TYPE" => headers["Content-Type"],
      }

      result = JSON.parse(InventoryService.send_request(payload))

      result = DirectResponse.new result["status"], result["headers"], result["body"]

      # puts "***** #{result.code} #{result.message}"
      # result.each_header { |k,v| puts "***** #{k}: #{v}" }
      # puts "***** START BODY"
      # puts result.body
      # puts "***** END BODY"

      # ms = Benchmark.ms { result = http.send(method, path, *arguments) }
      # puts "--> %d %s (%d %.0fms)" % [result.code, result.message, result.body ? result.body.length : 0, ms] if logger
      handle_response(result)
    end
  end

  class InventoryService
    @@child_process = nil
    def self.start
      unless @@child_process
        # TODO: remove hard-coded path
        rackup_file_contents = <<-EOF
$: << '~/src/rack-direct/lib'
require 'rack_direct'

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
        puts "Starting the inventory service"
        cmd = "cd ~/src/jambool/trunk/data/inventory/ && rake db:test:prepare && rackup --server #{RACK_DIRECT_ALIAS} #{tmpfile.path}"
        puts cmd
        @@child_process = IO.popen cmd, "w+"
        # set ServiceInterface::InventoryApi::Base.site to point at that server
        ServiceInterface::InventoryApi::Base.site = "rack-direct://inventory"

        at_exit do
          File.unlink tmppath
          RackDirect::InventoryService.stop
        end
      end
    end

    def self.send_request rack_request_env

      if @@child_process

        rack_request_env["direct_request.unique_id"] = Guid.new.to_s

        @@child_process.puts rack_request_env.to_json
        @@child_process.puts ""

        response = ""
        in_response = false
        while true
          line = @@child_process.gets
          # puts "SERVER: #{line.strip}"
          if line.strip == "BEGIN #{rack_request_env["direct_request.unique_id"]}"
            in_response = true
            next
          elsif line.strip == "END #{rack_request_env["direct_request.unique_id"]}"
            break
          elsif in_response
            response += line
          else
            puts "SERVER: #{line.strip}"
          end
        end
        # puts "Final response: #{response}"
        response
      end

    end

    def self.stop
      if @@child_process
        print "Killing server..."
        @@child_process.puts "EXIT"
        @@child_process.puts ""
        @@child_process = nil
        Process.waitall
        puts "done."
      end
    end
  end

end
