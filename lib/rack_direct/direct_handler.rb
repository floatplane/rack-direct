require 'json'
require 'pp'

module RackDirect
  class DirectHandler
    def self.run(app, options=nil)
      @@verbose = options[:verbose]
      request = []
      while true
        line = STDIN.gets
        if line.blank?
          begin
            break if request[0] == "EXIT" || request[0].blank?
            payload = JSON.parse request[0]
            uri = payload["uri"]

            #
            # Fix up names in the hash to match what MockRequest is looking for
            payload[:input] = payload["body"]
            payload[:method] = payload["method"]
            payload[:params] = payload["params"]

            rack_env = Rack::MockRequest.env_for(uri, payload)
            rack_env["rack.errors"] = STDERR

            self.serve app, rack_env

          rescue => e
            STDERR.puts "Exception: #{e}"
            e.backtrace.each { |x| STDERR.puts x }
          ensure
            request = []
          end
        else
          request << line.strip
        end
      end
    end

    def self.serve(app, env)
      if @@verbose
        STDERR.puts "Calling serve"
        STDERR.puts("Rack env:")
        $> = STDERR
        pp rack_env
        $> = STDOUT
        STDERR.puts("Body: #{rack_env["rack.input"].string}")
      end

      status, headers, body = app.call(env)

      begin
        body_string = ""
        body.each { |part| body_string += part }
        result = {
          "status" => status,
          "headers" => headers,
          "body" => body_string
        }

        if @@verbose
          STDERR.puts "Sending result (#{status})"
          STDERR.puts result.to_json
        end

        unique_id = env["direct_request.unique_id"]

        STDOUT.puts "BEGIN #{unique_id}"
        STDOUT.puts result.to_json
        STDOUT.puts "END #{unique_id}"
        STDOUT.flush

        if @@verbose
          send_headers status, headers, STDERR
          send_body body, STDERR
        end
      ensure
        body.close  if body.respond_to? :close
      end
    end

    def self.send_headers(status, headers, file = STDOUT)
      file.print "Status: #{status}\r\n"
      headers.each { |k, vs|
        vs.each { |v|
          file.print "#{k}: #{v}\r\n"
        }
      }
      file.print "\r\n"
      file.flush
    end

    def self.send_body(body, file = STDOUT)
      body.each { |part|
        file.print part
        file.flush
      }
    end
  end
end
