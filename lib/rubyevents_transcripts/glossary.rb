# frozen_string_literal: true

module RubyEventsTranscripts
  # The words a speech recogniser gets wrong in a Ruby talk - "Prism", "IRB",
  # "ruby_llm", "Ractor", the speakers' names - collected from the talk's
  # metadata and slides, for the model to spell them right.
  class Glossary
    # code-ish tokens and capitalised words; plain lowercase prose is not
    TOKEN = /[A-Za-z][A-Za-z0-9]*(?:(?:::|[._#-])[A-Za-z0-9]+)*[?!]?/
    COMMON = %w[The This That These Those There Here What When Where Why How And But For With From Into
                Your You Our We They It Its Let Lets Don Can Will Just Not All Any One Two Three New Use
                Using Thank Thanks Questions Agenda Today About Me Example Examples Demo Summary Conclusion
                If Else End Do Is Are Was Be By Of On In At To As So Or No Yes Ok Okay A An I].freeze

    def self.build(talk, slides_text, limit: 120) = new(talk, slides_text).terms(limit)

    def initialize(talk, slides_text)
      @talk = talk
      @slides = slides_text.to_s
    end

    # the talk's own names first, then the slides' terms by frequency
    def terms(limit)
      named = (@talk.speakers + [@talk.event_name] + @talk.title.scan(TOKEN).select { |w| term?(w) }).uniq
      counts = Hash.new(0)
      @slides.scan(TOKEN).each do |word|
        counts[word] += 1 if term?(word)
        # Prism.parse and RubyVM::AST mention Prism and RubyVM, too
        head = word[/\A[A-Z][A-Za-z0-9]*(?=\.|::)/]
        counts[head] += 1 if head && term?(head)
      end
      # once is enough for code (snake_case, Foo::Bar, CamelCase); a plain
      # capitalised word must come back
      ranked = counts.select { |word, n| n > 1 || code?(word) }.sort_by { |word, n| [-n, word] }.map(&:first)
      options = @slides.scan(/(?<![\w-])--[a-z][a-z0-9-]+/).uniq   # irb --type-completor
      (named + options + ranked).reject(&:empty?).uniq.first(limit)
    end

    private

    def term?(word)
      return false if word.length < 2 || COMMON.include?(word)

      code?(word) || word.match?(/\A[A-Z]/)
    end

    def code?(word)
      word.match?(/[_:.#]|[a-z][A-Z]|\A[A-Z]{2,}\z|[?!]\z/) && word.length > 2
    end
  end
end
