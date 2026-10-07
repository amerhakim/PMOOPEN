require "net/http"
require "json"

module VendorManagement
  module PoReader
    # Talks to the local Ollama server (same one RAID Log uses) -- the PO
    # files never leave this machine. Slow on CPU, so the timeout is long
    # and everything runs in a background job.
    class OllamaClient
      class Error < StandardError; end
      class Busy < StandardError; end

      DEFAULT_HOST = "http://host.docker.internal:11434".freeze
      DEFAULT_MODEL = "qwen2.5:7b-instruct".freeze

      # deadline: the moment after which the model is not asked any more (a read must stay quick)
      def initialize(host: nil, model: nil, timeout: 900, deadline: nil)
        @host = host || ENV["VENDOR_MANAGEMENT_OLLAMA_HOST"] || ENV["RAID_LOG_OLLAMA_HOST"] || DEFAULT_HOST
        @model = model || ENV["VENDOR_MANAGEMENT_OLLAMA_MODEL"] || ENV["RAID_LOG_OLLAMA_MODEL"] || DEFAULT_MODEL
        @timeout = timeout
        @deadline = deadline
      end

      # Returns the parsed JSON object the model answered with.
      def generate_json(prompt, max_tokens: 2048)
        attempts = 0
        begin
          attempts += 1
          request_json(prompt, max_tokens)
        rescue EOFError, IOError, Errno::ECONNRESET, Errno::EPIPE, Busy
          # the model server restarted or could not load the model yet (this
          # server is short on memory): give it a moment and try again
          raise Error, "The local AI stopped answering" if attempts >= 3 || time_left < 25

          sleep 20
          retry
        end
      end

      private

      def time_left
        @deadline ? @deadline - Time.now : @timeout
      end

      def request_json(prompt, max_tokens)
        raise Error, "The AI had no time left (a file is read within 30 seconds)" if time_left < 4

        body = {
          model: @model, prompt:, stream: false, format: "json",
          options: { temperature: 0, num_predict: max_tokens, num_ctx: 6144 }
        }
        uri = URI.join(@host, "/api/generate")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 10
        http.read_timeout = [@timeout, time_left].min
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
        request.body = body.to_json
        response = http.request(request)
        raise Busy, "Ollama answered #{response.code}" if response.code.to_i >= 500
        raise Error, "Ollama answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        text = JSON.parse(response.body)["response"].to_s
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise Error, "The AI answered with invalid JSON (#{e.message.truncate(80)})"
      rescue Net::ReadTimeout => e
        raise Error, "The AI was too slow (#{@deadline ? 'the 30 second limit was reached' : e.class.name.demodulize})"
      rescue Errno::ECONNREFUSED, Net::OpenTimeout, SocketError => e
        raise Error, "Could not reach the local AI (#{e.class.name.demodulize})"
      end
    end
  end
end
