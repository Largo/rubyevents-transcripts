# frozen_string_literal: true

require_relative "test_helper"

class EnhancerTest < Minitest::Test
  include TestHelpers

  def enhancer(chat, **options)
    RubyEventsTranscripts::Enhancer.new(talk: talk, chat: chat, language: "en", source_language: "en",
                                        glossary: %w[Prism IRB], **options)
  end

  # pairs of lines, cleaned up
  def pairs(count)
    { "paragraphs" => (1..count).each_slice(2).map { |a, b = a| { "first" => a, "last" => b, "text" => "Lines #{a} to #{b}." } } }
  end

  def test_paragraph_times_come_from_the_captions
    chat, = FakeChat.factory { |_text, count| pairs(count) }
    result = enhancer(chat).call(lines(6))
    assert_equal 3, result.cues.size
    assert_equal [0.0, 7.5], [result.cues[0].start, result.cues[0].finish], "line 1's start, line 2's end"
    assert_equal [16.0, 23.5], [result.cues[2].start, result.cues[2].finish]
    assert_equal "Lines 5 to 6.", result.cues[2].text
    assert_equal 0, result.fallback_chunks
  end

  def test_a_long_talk_goes_in_chunks_and_all_of_it_comes_back
    chat, chats = FakeChat.factory { |_text, count| pairs(count) }
    result = enhancer(chat, max_seconds: 60).call(lines(100))   # 400 s
    assert_operator chats.size, :>=, 6
    assert_equal 0.0, result.cues.first.start
    assert_equal lines(100).last.finish, result.cues.last.finish
    result.cues.each_cons(2) { |a, b| assert_operator a.finish, :<=, b.start }
  end

  def test_an_answer_that_skips_a_line_is_asked_again
    answers = [{ "paragraphs" => [{ "first" => 1, "last" => 2, "text" => "One." }, { "first" => 4, "last" => 4, "text" => "Four." }] },
               pairs(4)]
    chat, chats = FakeChat.factory { |_text, _count| answers.shift }
    result = enhancer(chat).call(lines(4))
    assert_equal 2, chats.size
    assert_includes chats.last.requests.first, "starts at 4, expected 3"
    assert_equal 2, result.cues.size
    assert_equal 0, result.fallback_chunks
  end

  def test_a_chunk_the_model_keeps_getting_wrong_keeps_its_raw_lines
    chat, = FakeChat.factory { |_text, _count| { "paragraphs" => [{ "first" => 1, "last" => 1, "text" => "Only one." }] } }
    result = enhancer(chat).call(lines(3))
    assert_equal 1, result.fallback_chunks
    assert_equal "line 1 so um yeah line 2 so um yeah line 3 so um yeah", result.cues.map(&:text).join(" ")
    assert_equal [0.0, 11.5], [result.cues.first.start, result.cues.last.finish]
  end

  def test_a_failing_request_falls_back_too
    chat = -> { raise "rate limited" }
    result = enhancer(chat).call(lines(2))
    assert_equal 1, result.fallback_chunks
    assert_equal 1, result.cues.size
  end

  def test_a_json_string_answer_and_symbol_keys_work
    chat, = FakeChat.factory { |_text, count| JSON.generate(pairs(count)) }
    assert_equal 2, enhancer(chat).call(lines(4)).cues.size
    chat, = FakeChat.factory { |_text, count| { paragraphs: [{ first: 1, last: count, text: "All." }] } }
    assert_equal ["All."], enhancer(chat).call(lines(3)).cues.map(&:text)
  end

  def test_the_request_carries_context_and_numbered_lines
    chat, chats = FakeChat.factory { |_text, count| pairs(count) }
    enhancer(chat, max_seconds: 10).call(lines(6))
    first, second = chats.map { |c| c.requests.first }
    assert_includes first, "Talk: Keynote: Writing Weird Code"
    assert_includes first, "Glossary: Prism, IRB"
    assert_includes first, "1 [00:00:00] line 1 so um yeah"
    assert_includes second, "Previous paragraph (context only, do not repeat it): Lines"
    assert_includes chats.first.instructions, "Cover every line from 1 to"
  end

  def test_a_translation_says_so
    chat, chats = FakeChat.factory { |_text, count| pairs(count) }
    RubyEventsTranscripts::Enhancer.new(talk: talk, chat: chat, language: "en", source_language: "ja").call(lines(2))
    assert_includes chats.first.instructions, "The captions are in Japanese. Translate them faithfully into English."
  end
end
