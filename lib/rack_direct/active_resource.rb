require 'active_resource'
require 'rack_direct/service'
require 'rack_direct/direct_response'

module RackDirect

  class ActiveResource::Connection

    def request_with_filtering_rack_direct(method, path, *arguments)

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
        "uri" => "http://#{site.host}#{path}",
        "method" => method.to_s.upcase,
        "body" => body.to_s,
        "CONTENT_TYPE" => headers["Content-Type"] || "text/plain;charset=utf-8",
      }

      result = JSON.parse(Service.send_request(site.host, payload))

      result = DirectResponse.new result["status"], result["headers"], result["body"]

      Service.log site.host, "#{result.code} #{result.message}"
      result.each_header { |k,v| Service.log site.host, "#{k}: #{v}" }
      Service.log site.host, "START BODY"
      Service.log site.host, result.body
      Service.log site.host, "END BODY"

      handle_response(result)
    end

    # TODO: requiring this more than once will not do the right thing
    alias_method :request_without_filtering_rack_direct, :request
    alias_method :request, :request_with_filtering_rack_direct

  end

end
