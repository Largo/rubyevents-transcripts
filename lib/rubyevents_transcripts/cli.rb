# frozen_string_literal: true

require "optparse"

module RubyEventsTranscripts
  # bin/transcribe
  class CLI
    USAGE = <<~TEXT
      Usage:
        transcribe list  SERIES/EVENT                 the event's talks: id, language, slides
        transcribe talk  SERIES/EVENT TALK_ID [opts]  one talk (id or YouTube video id)
        transcribe event SERIES/EVENT [opts]          every talk with a YouTube video, skipping done ones

      Options:
    TEXT

    def self.start(argv) = new.run(argv)

    def run(argv)
      options = { model: ENV.fetch("TRANSCRIPTS_MODEL", nil), provider: ENV.fetch("TRANSCRIPTS_PROVIDER", nil),
                  source: :captions, out: "transcripts" }
      parser = option_parser(options)
      command, event, talk_id = parser.parse(argv)
      catalog = Catalog.new(data_dir: options[:data])
      case command
      when "list" then list(catalog.talks(event || abort(parser.help)))
      when "talk" then transcriber(options).call(catalog.talk(event, talk_id || abort(parser.help)), **talk_options(options))
      when "event" then catalog.talks(event || abort(parser.help)).select(&:youtube?).each { |talk| each_talk(options, talk) }
      else abort(parser.help)
      end
    end

    private

    def option_parser(options)
      OptionParser.new do |o|
        o.banner = USAGE
        o.on("--model MODEL", "RubyLLM model (or TRANSCRIPTS_MODEL), e.g. gpt-5-mini, claude-sonnet-5-5, sonnet") { |v| options[:model] = v }
        o.on("--provider NAME", "RubyLLM provider (or TRANSCRIPTS_PROVIDER), e.g. claude_cli") { |v| options[:provider] = v }
        o.on("--source SOURCE", %w[captions audio], "captions (YouTube, default) or audio (yt-dlp + RubyLLM.transcribe)") { |v| options[:source] = v.to_sym }
        o.on("--languages LIST", "transcripts to write, e.g. ja,en (default: the talk's language, plus en)") { |v| options[:languages] = v.split(",") }
        o.on("--slides PATH_OR_URL", "slides to use instead of the talk's slides_url") { |v| options[:slides] = v }
        o.on("--minutes N", Integer, "only the first N minutes - for a trial run") { |v| options[:minutes] = v }
        o.on("--data DIR", "a checkout's data/ directory instead of GitHub (or RUBYEVENTS_DATA)") { |v| options[:data] = v }
        o.on("--out DIR", "where transcripts go (default: transcripts)") { |v| options[:out] = v }
        o.on("--force", "write transcripts that exist already") { options[:force] = true }
      end
    end

    def transcriber(options)
      abort("Which model? --model or TRANSCRIPTS_MODEL") unless options[:model]
      LLM.configure!
      Transcriber.new(model: options[:model], provider: options[:provider], source: options[:source],
                      writer: Writer.new(root: options[:out]), minutes: options[:minutes], force: options[:force])
    end

    def talk_options(options) = { languages: options[:languages], slides: options[:slides] }.compact

    def each_talk(options, talk)
      transcriber(options).call(talk, languages: options[:languages])
    rescue StandardError => e
      warn "#{talk.id}: #{e.message}"
    end

    def list(talks)
      talks.each do |talk|
        puts format("%-50s %-4s %-7s %s", talk.id, talk.language_code, talk.slides_url ? "slides" : "-", talk.title)
      end
    end
  end
end
