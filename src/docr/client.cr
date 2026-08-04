# Require necessary modules and files.
require "http/client"
require "socket"

require "./errors"

# Define the Docr module.
module Docr
  # Define the Docr::Client class for making HTTP requests to the Docker API.
  #
  # Subclasses HTTP::Client (rather than wrapping a single UNIXSocket handed
  # to HTTP::Client.new(io)) so it can actually reconnect: HTTP::Client's own
  # raw-IO constructor sets @reconnect = false, so once the daemon closes a
  # connection (or a response body isn't fully drained, desyncing the
  # HTTP/1.1 framing on a shared keep-alive connection - both are common
  # with the Docker API), every subsequent call on that client raises
  # "This HTTP::Client cannot be reconnected". Overriding the private #io
  # method instead - the same pattern HTTP::Client itself uses to lazily
  # (re)connect over TCP/TLS - lets a fresh UNIXSocket be opened on demand.
  class Client < HTTP::Client
    # Default Docker daemon socket path, matching the Docker CLI/SDKs' own
    # default.
    DEFAULT_SOCKET_PATH = "/var/run/docker.sock"

    @socket_path : String?

    # Initializes a new instance of the Docr::Client class talking to a
    # local UNIX socket (the common case - a local or rootless Docker/
    # Podman daemon).
    #
    # - socket_path: path to the Docker daemon's UNIX socket. Defaults to
    #   the DOCKER_HOST environment variable (a unix:// URL, the same
    #   convention the Docker CLI and every other Docker SDK honor - useful
    #   for rootless Docker/Podman, where the daemon socket usually isn't
    #   at DEFAULT_SOCKET_PATH and isn't reachable by an unprivileged user
    #   even when it is), falling back to DEFAULT_SOCKET_PATH if unset.
    def initialize(socket_path : String? = nil)
      super(host: "localhost")
      @socket_path = socket_path || docker_host_socket_path || DEFAULT_SOCKET_PATH
    end

    # Initializes a new instance of the Docr::Client class talking to a
    # *remote* Docker daemon over TCP, optionally TLS-secured - the
    # `tls` param is `HTTP::Client`'s own `TLSContext` (`nil` for plain
    # TCP, `true` for TLS with default verification, or an
    # `OpenSSL::SSL::Context::Client` for full control over
    # certs/verification - callers build that context, this class just
    # passes it straight through to the underlying `HTTP::Client`).
    def initialize(host : String, port : Int32, tls : HTTP::Client::TLSContext = nil)
      super(host: host, port: port, tls: tls)
      @socket_path = nil
    end

    private def docker_host_socket_path : String?
      ENV["DOCKER_HOST"]?.try(&.sub(/^unix:\/\//, ""))
    end

    # Lazily (re)connect over a UNIX socket instead of HTTP::Client's own
    # TCP/TLS logic - otherwise identical to how HTTP::Client#io works.
    # When constructed for a remote TCP(+TLS) daemon instead (no
    # @socket_path set), defers to HTTP::Client's own #io unchanged via
    # `super` - that's already exactly the TCP/TLS connection logic
    # needed here.
    private def io
      socket_path = @socket_path
      return super unless socket_path

      cached = @io
      return cached if cached
      unless @reconnect
        raise "This HTTP::Client cannot be reconnected"
      end

      socket = UNIXSocket.new(socket_path)
      socket.read_timeout = @read_timeout if @read_timeout
      socket.write_timeout = @write_timeout if @write_timeout
      socket.sync = false

      @io = socket
    end

    # Makes an HTTP request to the Docker API.
    #
    # - method: The HTTP method (e.g., "GET", "POST", "PUT", "DELETE").
    # - url: The URL or URI for the API endpoint.
    # - headers: Optional HTTP headers.
    # - body: Optional request body (e.g., JSON payload).
    # - &block: A block to process the HTTP response.
    def call(method : String, url : String | URI, headers : HTTP::Headers | Nil = nil, body : IO | Slice(UInt8) | String | Nil = nil, &)
      exec(method, url, headers, body) do |response|
        unless response.success?
          body = response.body_io?.try(&.gets_to_end) || "{\"message\": \"No response body\"}"
          error = Docr::Types::ErrorResponse.from_json(body)

          # Raise a custom DockerAPIError exception with the error message and status code.
          raise Docr::Errors::DockerAPIError.new(error.message, response.status_code)
        end

        # Yield the HTTP response to the provided block for further processing.
        yield response
      end
    end
  end
end
