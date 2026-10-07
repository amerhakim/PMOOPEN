require "open3"
require "tmpdir"
require "timeout"

module VendorManagement
  module PoReader
    # PDF -> text. Born-digital PDFs give their own text; scanned ones (the
    # usual signed + stamped POs) are rendered at 400 dpi, straightened and
    # OCR'd with tesseract in a layout-preserving mode so table columns stay
    # on one line.
    class PdfOcr
      class Error < StandardError; end

      MAX_PAGES = 8
      PARALLEL_PAGES = 2
      TEXT_PAGES = 40 # a text layer costs nothing to read; only scans are limited to MAX_PAGES
      DPI = 400
      MIN_TEXT_LAYER = 200
      Result = Struct.new(:text, :tsv_pages)

      def initialize(bytes)
        @bytes = bytes
      end

      def call
        Dir.mktmpdir("po_ai") do |dir|
          path = File.join(dir, "in.pdf")
          File.binwrite(path, @bytes)

          embedded = run("pdftotext", "-layout", "-l", TEXT_PAGES.to_s, path, "-").strip
          return Result.new(embedded, []) if embedded.length >= MIN_TEXT_LAYER

          run("pdftoppm", "-r", DPI.to_s, "-gray", "-png", "-l", MAX_PAGES.to_s, path, File.join(dir, "pg"))
          pages = Dir.glob(File.join(dir, "pg*.png")).sort
          raise Error, "The PDF has no pages to read" if pages.empty?

          # pages are read side by side (two cores each); the scan is what takes the time
          results = pages.each_slice(PARALLEL_PAGES).flat_map do |batch|
            batch.map { |png| Thread.new { ocr_page(png) } }.map(&:value)
          end
          texts = results.each_with_index.map { |(text, _tsv), index| "=== PAGE #{index + 1} ===\n#{text}" }
          Result.new(texts.join("\n\n"), results.map(&:last))
        end
      end

      private

      def ocr_page(png)
        cleaned = png.sub(/\.png\z/, "_c.png")
        source = system_quiet("convert", png, "-deskew", "40%", "-level", "15%,85%", cleaned) ? cleaned : png
        base = png.sub(/\.png\z/, "_ocr")
        run("tesseract", source, base, "--psm", "4", "-l", "eng", "-c", "preserve_interword_spaces=1", "txt", "tsv",
            env: { "OMP_THREAD_LIMIT" => "2" })
        [File.read("#{base}.txt"), File.read("#{base}.tsv")]
      end

      def system_quiet(*cmd)
        _out, _err, status = Timeout.timeout(120) { Open3.capture3(*cmd) }
        status.success?
      rescue StandardError
        false
      end

      def run(*cmd, env: {})
        out, err, status = Timeout.timeout(300) { Open3.capture3(env, *cmd) }
        raise Error, "#{cmd.first} failed: #{err.to_s.strip.truncate(120)}" unless status.success?

        out
      rescue Errno::ENOENT
        raise Error, "#{cmd.first} is not installed on this server"
      rescue Timeout::Error
        raise Error, "#{cmd.first} took too long"
      end
    end
  end
end
