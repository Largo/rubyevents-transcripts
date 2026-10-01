# frozen_string_literal: true

module RubyEventsTranscripts
  # One talk from start to finish: its cues (YouTube captions, or the audio),
  # its slides' vocabulary, a transcript in the talk's language and - for a
  # talk not in English - an English one, written by Writer.
  class Transcriber
    def initialize(model:, provider: nil, source: :captions, writer: Writer.new, cache_dir: "cache",
                   minutes: nil, force: false, log: ->(line) { warn(line) })
      @model = model
      @provider = provider
      @source = source.to_sym
      @writer = writer
      @cache_dir = cache_dir
      @minutes = minutes
      @force = force
      @log = log
    end

    # the files written (none when all were there already); +slides+
    # overrides the talk's slides_url (a path or URL)
    def call(talk, languages: nil, slides: nil)
      languages ||= [talk.language_code, "en"].uniq
      todo = @force ? languages : languages.reject { |language| @writer.exist?(talk, language) }
      return [] if todo.empty?

      @log.call("#{talk.id} (#{talk.language_code}): #{talk.title}")
      slides_text = Slides.new(cache_dir: @cache_dir).text(talk, slides || talk.slides_url)
      glossary = Glossary.build(talk, slides_text)
      @log.call("  slides: #{slides_text.empty? ? 'none' : "#{slides_text.length} chars"}, glossary: #{glossary.size} terms")
      source_language, generated, cues = source_cues(talk, glossary)
      cues = cues.take_while { |cue| cue.start < @minutes * 60 } if @minutes

      todo.map do |language|
        result = Enhancer.new(talk: talk, chat: -> { LLM.chat(model: @model, provider: @provider) }, language: language,
                              source_language: source_language, glossary: glossary, log: ->(line) { @log.call("  #{language} #{line}") })
                         .call(cues)
        meta = { "source" => @source.to_s, "source_language" => source_language, "auto_generated_source" => generated,
                 "translated" => source_language != language, "model" => @model, "provider" => @provider.to_s,
                 "slides" => !slides_text.empty?, "glossary_terms" => glossary.size, "chunks" => result.chunks,
                 "fallback_chunks" => result.fallback_chunks, "partial_minutes" => @minutes }.compact
        @writer.write(talk, language: language, cues: result.cues, meta: meta).tap { |path| @log.call("  wrote #{path}") }
      end
    end

    private

    # [language, auto-generated?, cues]
    def source_cues(talk, glossary)
      if @source == :audio
        [talk.language_code, true, Audio.new(cache_dir: @cache_dir).cues(talk, glossary: glossary)]
      else
        track = Captions.new(cache_dir: @cache_dir).fetch(talk) or
          raise "#{talk.id}: YouTube has no captions for #{talk.video_id} - try --source audio"
        [track.language, track.generated, track.cues]
      end
    end
  end
end
