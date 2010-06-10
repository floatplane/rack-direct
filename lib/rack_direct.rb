require 'rack_direct/direct_handler'
RACK_DIRECT_ALIAS = 'rack-direct'

require 'rack'
require 'active_resource'
require 'open3'
require 'rack_direct/guid'
require 'tmpdir'

# TODO: 
# when required, run an initializer that plugs into ActiveResource
# support option to nuke/not nuke the testdb
# auto-generate name as last element of path if it's not specified?

module RackDirect

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

    def request_with_filtering_rack_direct(method, path, *arguments)

      debugger

      # passthrough anything we don't understand
      return request_without_filtering_rack_direct(method, path, *arguments) unless site.scheme.match(/^rack-direct/)

      # puts "#{method.to_s.upcase} #{site.scheme}://#{site.host}:#{site.port}#{path}" if logger
      result = nil

      headers = arguments.last
      body = arguments.first if arguments.length > 1

      payload = {
        # Note: We can't pass through a site.scheme of 'rack-direct'
        # because the Rack instance on the receiving end will freak
        # out. So we use http in the URI here.
        "uri" => "http://#{site.host}:#{site.port}#{path}",
        "method" => method.to_s.upcase,
        "body" => body.to_s,
        "CONTENT_TYPE" => headers["Content-Type"] || "text/plain;charset=utf-8",
      }

      result = JSON.parse(Service.send_request(site.host, payload))

      result = DirectResponse.new result["status"], result["headers"], result["body"]

      if Service.verbose_logging
        puts "***** #{result.code} #{result.message}"
        result.each_header { |k,v| puts "***** #{k}: #{v}" }
        puts "***** START BODY"
        puts result.body
        puts "***** END BODY"
      end

      handle_response(result)
    end

    # TODO: requiring this more than once will not do the right thing
    alias_method :request_without_filtering_rack_direct, :request
    alias_method :request, :request_with_filtering_rack_direct

  end

  class Service

    class << self
      attr_accessor :verbose_logging
    end

    @@services = {}
    def self.start name, path
      unless @@services[name]
        # TODO: remove hard-coded path
        rackup_file_contents = <<-EOF
$: << '~/src/rack-direct/lib'
require 'rack_direct'
Rack::Handler.register('#{RACK_DIRECT_ALIAS}', 'RackDirect::DirectHandler')
puts "RackDirect::DirectHandler registered"

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

        # TODO: check path to make sure a Rails app exists there
        print "Starting service rack-direct://#{name}..."
        cmd = "cd #{path} && rake db:test:prepare && rackup --server #{RACK_DIRECT_ALIAS} #{tmpfile.path} 2>&1"
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
  end

end
