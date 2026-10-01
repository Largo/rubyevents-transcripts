# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/rubyevents_transcripts"

module TestHelpers
  Talk = RubyEventsTranscripts::Talk
  Cue = RubyEventsTranscripts::Cue

  def talk(**overrides)
    Talk.new(event_path: "rubykaigi/rubykaigi-2024", id: "tomoya-ishida-rubykaigi-2024", title: "Keynote: Writing Weird Code",
             speakers: ["Tomoya Ishida"], event_name: "RubyKaigi 2024", date: "2024-05-15", language: "Japanese",
             video_provider: "youtube", video_id: "k6QGq5uGhgU", slides_url: nil,
             description: "Ruby is a great language to write readable code.", **overrides)
  end

  # one caption line every 4 seconds
  def lines(count, from: 0)
    (from...(from + count)).map { |i| Cue.new(start: i * 4.0, finish: (i * 4.0) + 3.5, text: "line #{i + 1} so um yeah") }
  end

  # RubyLLM's chat as the enhancer uses it: a fresh one per request; the
  # answer comes from the block, given the request text and the lines' count
  class FakeChat
    Reply = Data.define(:content)
    attr_reader :requests, :instructions

    def self.factory(&answer)
      chats = []
      maker = -> { new(answer).tap { |chat| chats << chat } }
      [maker, chats]
    end

    def initialize(answer)
      @answer = answer
      @requests = []
    end

    def with_instructions(text) = (@instructions = text) && self
    def with_schema(_schema) = self

    def ask(text)
      @requests << text
      count = text.lines.count { |line| line.match?(/\A\d+ \[/) }
      Reply.new(@answer.call(text, count))
    end
  end
end
