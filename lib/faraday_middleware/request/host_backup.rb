require 'faraday'

module FaradayMiddleware
  # Catches exceptions and tries to send request to the backup host.
  #
  # By default, it catches TimeoutError and ConnectionFailed exceptions. It can
  # be configured.
  #
  # Examples
  #
  #   Faraday.new do |conn|
  #     conn.use FaradayMiddleware::HostBackup, host: "example.com",
  #                          exceptions: [CustomException, 'Timeout::Error']
  #     conn.adapter ...
  #   end
  class HostBackup < Faraday::Middleware
    class Options < Faraday::Options.new(:host, :exceptions)
      def self.from(value)
        if Fixnum === value
          new(value)
        else
          super(value)
        end
      end

      def exceptions
        Array(self[:exceptions] ||= [Errno::ETIMEDOUT, 'Timeout::Error',
                                     Faraday::ConnectionFailed, Faraday::Error::TimeoutError])
      end

    end

    def initialize(app, options = nil)
      super(app)
      @options = Options.from(options)
      @errmatch = build_exception_matcher(@options.exceptions)
    end

    def call(env)
      begin
        @app.call(env)
      rescue @errmatch
        unless env[:url].host == @options.host
          env[:url].host = @options.host
          retry
        end

        raise
      end
    end

    # Private: construct an exception matcher object.
    #
    # An exception matcher for the rescue clause can usually be any object that
    # responds to `===`, but for Ruby 1.8 it has to be a Class or Module.
    def build_exception_matcher(exceptions)
      matcher = Module.new
      (class << matcher; self; end).class_eval do
        define_method(:===) do |error|
          exceptions.any? do |ex|
            if ex.is_a? Module then error.is_a? ex
            else error.class.to_s == ex.to_s
            end
          end
        end
      end
      matcher
    end
  end
end