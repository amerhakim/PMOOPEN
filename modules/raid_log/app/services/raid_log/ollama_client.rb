require "net/http"
require "uri"
require "json"

module RaidLog
  # Talks to a local Ollama instance (http://localhost:11434 by default) --
  # no external network access, no API key. This is the only AI backend the
  # RAID log feature uses, by design: the app must keep working with zero
  # internet dependency.
  class OllamaClient
    class Error < StandardError; end

    DEFAULT_HOST = "http://localhost:11434".freeze
    DEFAULT_MODEL = "qwen2.5:7b-instruct".freeze
    REQUEST_TIMEOUT = 180

    def initialize(host: ENV.fetch("RAID_LOG_OLLAMA_HOST", DEFAULT_HOST),
                    model: ENV.fetch("RAID_LOG_OLLAMA_MODEL", DEFAULT_MODEL))
      @host = host
      @model = model
    end

    def available?
      uri = URI.join(@host, "/api/version")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 3
      http.read_timeout = 3
      http.request(Net::HTTP::Get.new(uri)).is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    # Single-turn prompt, returns the raw text response.
    # format: "json" asks Ollama to constrain output to syntactically valid JSON.
    def generate(prompt, format: nil)
      body = { model: @model, prompt:, stream: false }
      body[:format] = format if format

      JSON.parse(post("/api/generate", body)).fetch("response")
    end

    private

    def post(path, body)
      uri = URI.join(@host, path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = REQUEST_TIMEOUT

      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = body.to_json

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Local AI service returned #{response.code}: #{response.body}"
      end

      response.body
    rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "Could not reach the local AI service at #{@host} (#{e.class}: #{e.message})"
    end
  end
end
