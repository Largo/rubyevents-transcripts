# frozen_string_literal: true

require "net/http"
require "uri"
require "fileutils"
require "open3"
require "pdf-reader"

module RubyEventsTranscripts
  # The text of a talk's slides: the PDF behind its slides_url (Google Drive,
  # Speaker Deck or a direct link) or a local file, read with pdftotext when
  # it is installed and with pdf-reader otherwise. Cached under
  # cache/<video_id>/.
  class Slides
    MAX_BYTES = 80_000_000

    def initialize(cache_dir: "cache")
      @cache_dir = cache_dir
    end

    # the slides' text, "" when there are none or they cannot be read
    def text(talk, source = talk.slides_url)
      return "" if source.nil? || source.to_s.strip.empty?

      dir = File.join(@cache_dir, talk.video_id)
      cached = File.join(dir, "slides.txt")
      return File.read(cached, encoding: "UTF-8") if File.exist?(cached)

      pdf = File.file?(source.to_s) ? source.to_s : download(source.to_s, File.join(dir, "slides.pdf"))
      text = pdf ? extract(pdf) : ""
      FileUtils.mkdir_p(dir)
      File.write(cached, text)
      text
    end

    private

    def download(url, path)
      return path if File.exist?(path)

      body = fetch_pdf(url) or return nil
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, body)
      path
    end

    def fetch_pdf(url)
      case url
      when %r{drive\.google\.com/file/d/([\w-]+)}, %r{drive\.google\.com/open\?id=([\w-]+)}
        google_drive(Regexp.last_match(1))
      when %r{speakerdeck\.com/}
        page = get(url)
        link = page&.body.to_s[%r{https://files\.speakerdeck\.com/presentations/[^"']+\.pdf}]
        link && pdf_or_nil(get(link))
      else
        pdf_or_nil(get(url))
      end
    end

    # Small files come at once; big ones first answer with a "can't scan for
    # viruses" page whose form carries the real download.
    def google_drive(id)
      response = get("https://drive.google.com/uc?export=download&id=#{id}")
      return pdf_or_nil(response) unless response&.body.to_s.include?("<form")

      action = response.body[/action="([^"]+)"/, 1] or return nil
      fields = response.body.scan(/name="([^"]+)" value="([^"]*)"/).to_h
      pdf_or_nil(get("#{action}?#{URI.encode_www_form(fields)}"))
    end

    def pdf_or_nil(response)
      body = response&.body.to_s
      body.start_with?("%PDF") ? body : nil
    end

    def get(url, redirects = 5)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => "rubyevents-transcripts"))
      end
      return get(URI.join(url, response["location"]).to_s, redirects - 1) if response.is_a?(Net::HTTPRedirection) && redirects.positive?
      return nil unless response.is_a?(Net::HTTPSuccess) && response.body.to_s.bytesize <= MAX_BYTES

      response
    rescue StandardError
      nil
    end

    def extract(pdf)
      # (Japanese PDFs make it warn about missing CMaps on stderr; the text is fine)
      text, _warnings, status = Open3.capture3("pdftotext", "-layout", pdf, "-")
      return text.force_encoding(Encoding::UTF_8).scrub if status.success?

      reader_text(pdf)
    rescue Errno::ENOENT
      reader_text(pdf)
    end

    def reader_text(pdf)
      PDF::Reader.new(pdf).pages.map(&:text).join("\n\f\n")
    rescue StandardError
      ""
    end
  end
end
