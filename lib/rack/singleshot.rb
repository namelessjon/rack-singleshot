require 'rack'

module Rack
  module Handler
    class SingleShot
      CRLF = "\r\n"

      def self.run(app, options = {})
        stdin   = options.fetch(:stdin, $stdin)
        stdout  = options.fetch(:stdout, $stdout)

        stdin.binmode = true  if stdin.respond_to?(:binmode=)
        stdout.binmode = true if stdout.respond_to?(:binmode=)

        new(app, stdin, stdout).run
      end

      def initialize(app, stdin, stdout)
        @app, @stdin, @stdout = app, stdin, stdout
      end

      def run
        request = read_request

        status, headers, body = @app.call(request)

        write_response(status, headers, body)
      ensure
        @stdout.close
        exit
      end

      def read_request
        buffer, extra = drain(@stdin, CRLF * 2)

        heading, buffer = buffer.split(CRLF, 2)

        verb, path, version = heading.split(' ')

        headers = parse_headers(buffer)

        if length = request_body_length(verb, headers)
          body = StringIO.new(extra + @stdin.read(length - extra.size))
        else
          body = StringIO.new(extra)
        end

        env_for(verb, path, version, headers, body)
      end

      def write_response(status, headers, body)
        @stdout.write(['HTTP/1.1', status, Rack::Utils::HTTP_STATUS_CODES[status.to_i]].join(' ') << CRLF)

        headers.each do |key, values|
          values.split("\n").each do |value|
            @stdout.write([key, value].join(": ") << CRLF)
          end
        end

        @stdout.write(CRLF)

        body.each do |chunk|
          @stdout.write(chunk)
        end
      end

      def parse_headers(raw_headers)
        raw_headers.split(CRLF).inject({}) do |h, pair|
          key, value = pair.split(": ")
          h.update(header_key(key) => value)
        end
      end

      def request_body_length(verb, headers)
        return if %w[ POST PUT ].include?(verb.upcase)

        if length = headers['CONTENT_LENGTH']
          length.to_i
        end
      end

      def drain(socket, stop_at, chunksize = 1024)
        buffer = ''

        while(chunk = socket.readpartial(chunksize))
          buffer << chunk

          if buffer.include?(stop_at)
            buffer, extra = buffer.split(stop_at, 2)

            return buffer, extra
          end
        end
      rescue EOFError
        return buffer, ''
      end

      def env_for(verb, path, version, headers, body)
        env = headers

        scheme = ['yes', 'on', '1'].include?(env['HTTPS']) ? 'https' : 'http'
        host   = env['SERVER_NAME'] || env['HTTP_HOST']

        uri = URI.parse([scheme, '://', host, path].join)

        env.update 'REQUEST_METHOD' => verb
        env.update 'SCRIPT_NAME'    => ''
        env.update 'PATH_INFO'      => uri.path
        env.update 'QUERY_STRING'   => uri.query || ''
        env.update 'SERVER_NAME'    => uri.host
        env.update 'SERVER_PORT'    => uri.port.to_s

        env.update 'rack.version'       => Rack::VERSION
        env.update 'rack.url_scheme'    => uri.scheme
        env.update 'rack.input'         => body
        env.update 'rack.errors'        => $stderr
        env.update 'rack.multithread'   => false
        env.update 'rack.multiprocess'  => false
        env.update 'rack.run_once'      => true

        env
      end

      def header_key(key)
        key = key.upcase.gsub('-', '_')

        %w[CONTENT_TYPE CONTENT_LENGTH SERVER_NAME].include?(key) ? key : "HTTP_#{key}"
      end
    end

    register 'singleshot', 'Rack::Handler::SingleShot'
  end
end
