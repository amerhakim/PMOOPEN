require "open3"
require "tmpdir"

module MsProjectImport
  # Shells out to the vendored MPXJ (Java) library to convert an uploaded
  # MS Project file (.mpp, .xml, .mpx, ...) into MPXJ's JSON schema.
  # Runs fully offline: the jar and all its dependencies are vendored under
  # vendor/mpxj, no network access is made at any point.
  class ParseService
    MPXJ_HOME = Rails.root.join("modules/ms_project_import/vendor/mpxj")
    MPXJ_MAIN_CLASS = "org.mpxj.sample.MpxjConvert"

    class ConversionError < StandardError; end

    def initialize(input_path)
      @input_path = input_path
    end

    def call
      Dir.mktmpdir("ms_project_import") do |dir|
        output_path = File.join(dir, "converted.json")
        run_mpxj!(output_path)

        JSON.parse(File.read(output_path), symbolize_names: true)
      end
    end

    private

    attr_reader :input_path

    def run_mpxj!(output_path)
      classpath = "#{MPXJ_HOME.join('mpxj.jar')}:#{MPXJ_HOME.join('lib', '*')}"
      cmd = ["java", "-cp", classpath, MPXJ_MAIN_CLASS, input_path, output_path]

      _stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success? && File.exist?(output_path)
        raise ConversionError, "Could not read this file as an MS Project file: #{stderr.presence || 'unknown error'}"
      end
    end
  end
end
