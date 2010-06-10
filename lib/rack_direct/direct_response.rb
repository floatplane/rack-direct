require 'rack'

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

end
