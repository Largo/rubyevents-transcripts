# frozen_string_literal: true

require "json"

module RubyEventsTranscripts
  # Raw caption lines in, readable paragraphs out - with the captions' own
  # timings. Two things went wrong when a model rewrote whole transcripts
  # (rubyevents/rubyevents#452): timings were invented, and long talks came
  # back cut short. So:
  #
  # - the talk goes in chunks of a few minutes
  # - the model sees numbered caption lines and answers which numbers form a
  #   paragraph, and its text - never a timestamp; a paragraph's times are
  #   its first line's start and its last line's end
  # - every line of a chunk must be in exactly one paragraph, in order; an
  #   answer that skips or repeats a line is asked again, and after that the
  #   chunk keeps its raw lines (counted in Result#fallback_chunks)
  #
  # +language+ is the transcript's language; when the captions are in
  # another one (+source_language+), the model translates as it goes.
  class Enhancer
    Result = Data.define(:cues, :chunks, :fallback_chunks)

    SCHEMA = {
      type: "object",
      properties: {
        paragraphs: {
          type: "array",
          items: {
            type: "object",
            properties: { first: { type: "integer" }, last: { type: "integer" }, text: { type: "string" } },
            required: %w[first last text],
            additionalProperties: false
          }
        }
      },
      required: ["paragraphs"],
      additionalProperties: false
    }.freeze

    LANGUAGE_NAMES = { "en" => "English", "ja" => "Japanese", "de" => "German", "es" => "Spanish",
                       "pt" => "Portuguese", "fr" => "French", "it" => "Italian", "pl" => "Polish",
                       "nl" => "Dutch", "ko" => "Korean", "zh" => "Chinese", "ru" => "Russian",
                       "uk" => "Ukrainian", "tr" => "Turkish" }.freeze

    # +chat+ makes a fresh RubyLLM chat (or anything with with_instructions,
    # with_schema and ask) for each request
    def initialize(talk:, chat:, language:, source_language: language, glossary: [],
                   max_seconds: 240, max_chars: 3500, attempts: 2, log: nil)
      @talk = talk
      @chat = chat
      @language = language
      @source_language = source_language
      @glossary = glossary
      @max_seconds = max_seconds
      @max_chars = max_chars
      @attempts = attempts
      @log = log
    end

    def call(cues)
      chunks = chunk(cues)
      paragraphs = []
      fallbacks = 0
      chunks.each_with_index do |lines, index|
        @log&.call("chunk #{index + 1}/#{chunks.size} (#{Cue.stamp(lines.first.start)}, #{lines.size} lines)")
        enhanced = enhance(lines, paragraphs.last&.text)
        unless enhanced
          fallbacks += 1
          enhanced = raw_paragraphs(lines)
        end
        paragraphs.concat(enhanced)
      end
      Result.new(cues: paragraphs, chunks: chunks.size, fallback_chunks: fallbacks)
    end

    # consecutive lines, cut after about max_seconds or max_chars
    def chunk(cues)
      cues.each_with_object([]) do |cue, chunks|
        current = chunks.last
        full = current.nil? || cue.finish - current.first.start > @max_seconds ||
               current.sum { |c| c.text.length } + cue.text.length > @max_chars
        full ? chunks << [cue] : current << cue
      end
    end

    private

    def enhance(lines, previous)
      problem = nil
      @attempts.times do
        reply = ask(lines, previous, problem)
        paragraphs, problem = paragraphs_from(reply, lines)
        return paragraphs if paragraphs

        @log&.call("  answer rejected: #{problem}")
      end
      nil
    rescue StandardError => e
      @log&.call("  request failed: #{e.class}: #{e.message}")
      nil
    end

    def ask(lines, previous, problem)
      chat = @chat.call
      chat.with_instructions(instructions(lines.size))
      chat.with_schema(SCHEMA)
      chat.ask(request(lines, previous, problem)).content
    end

    # [paragraphs, nil] or [nil, what was wrong]
    def paragraphs_from(reply, lines)
      data = reply.is_a?(String) ? JSON.parse(reply) : reply
      items = Array(data && (data["paragraphs"] || data[:paragraphs]))
      return [nil, "no paragraphs"] if items.empty?

      expected = 1
      cues = items.map do |item|
        first, last, text = %w[first last text].map { |key| item[key] || item[key.to_sym] }
        return [nil, "a paragraph starts at #{first}, expected #{expected}"] unless first.to_i == expected
        return [nil, "paragraph #{first}..#{last} ends before it starts"] unless last.to_i >= first.to_i
        return [nil, "paragraph #{first}..#{last} is empty"] if text.to_s.strip.empty?

        expected = last.to_i + 1
        Cue.new(start: lines[first.to_i - 1].start, finish: lines[last.to_i - 1].finish, text: text.to_s.strip)
      end
      return [nil, "the paragraphs end at #{expected - 1}, expected #{lines.size}"] unless expected == lines.size + 1

      [cues, nil]
    rescue JSON::ParserError, NoMethodError, TypeError => e
      [nil, "unreadable answer (#{e.class})"]
    end

    def instructions(count)
      translate = @source_language == @language ? "" : <<~TEXT
        The captions are in #{name(@source_language)}. Translate them faithfully into #{name(@language)}.
      TEXT
      <<~TEXT
        You edit automatic captions of a talk at a Ruby conference into a readable transcript.
        You get numbered caption lines and return paragraphs: each one a range of line numbers
        (first..last) and its text.

        - Cover every line from 1 to #{count} exactly once, in order: the first paragraph starts
          at 1, each next one starts right after the previous one ends, the last one ends at #{count}.
        - Keep what the speaker says and how they say it. Fix words the recogniser clearly
          misheard - use the glossary for names, Ruby terms and code - and add punctuation and
          capitalisation. Drop filler words (um, uh, you know) and false starts. Do not
          summarise, shorten or add anything.
        - Never swap a word the speaker did say for a glossary term: a nickname stays the
          nickname, an explanation stays an explanation.
        - Where a stretch is garbled beyond repair (stray digits, noise), make sense of it from
          the context and the glossary - years, versions, names - or leave it out. Never copy
          noise into the text.
        - A paragraph is one thought, usually two to six sentences.
        - Write code, method and gem names as Ruby writes them: ruby_llm, Prism.parse,
          RubyVM::InstructionSequence.
        - A sound description such as [Music] or [Applause] stays as it is.
        - Write the text in #{name(@language)}.
        #{translate}
      TEXT
    end

    def request(lines, previous, problem)
      parts = ["Talk: #{@talk.title}", "Speakers: #{@talk.speakers.join(', ')}", "Event: #{@talk.event_name}"]
      parts << "Description: #{@talk.description.gsub(/\s+/, ' ')[0, 600]}" unless @talk.description.strip.empty?
      parts << "Glossary: #{@glossary.join(', ')}" if @glossary.any?
      parts << "Previous paragraph (context only, do not repeat it): #{previous}" if previous
      parts << "Your last answer was rejected: #{problem}. Cover every line exactly once." if problem
      numbered = lines.each_with_index.map { |cue, i| "#{i + 1} [#{Cue.stamp(cue.start)[0, 8]}] #{cue.text}" }
      [*parts, "", "Captions:", *numbered].join("\n")
    end

    # the chunk's lines as they are, in paragraphs of half a minute or so:
    # cut at a sentence's end after 30 s, anywhere after 60 s
    def raw_paragraphs(lines)
      groups = lines.each_with_object([]) do |cue, list|
        group = list.last
        age = group && cue.start - group.first.start
        new_group = group.nil? || age >= 60 || (age >= 30 && group.last.text.match?(/[.?!。？！]\z/))
        new_group ? list << [cue] : group << cue
      end
      groups.map { |group| Cue.new(start: group.first.start, finish: group.last.finish, text: group.map(&:text).join(" ")) }
    end

    def name(code) = LANGUAGE_NAMES.fetch(code, code)
  end
end
