# frozen_string_literal: true

require_relative "test_helper"

# Cues, talks from videos.yml, the glossary and the files written
class DataTest < Minitest::Test
  include TestHelpers

  def test_cue_times_round_trip_in_the_schemas_format
    assert_equal "00:03:01.200", Cue.stamp(181.2)
    assert_equal "01:00:00.000", Cue.stamp(3600)
    assert_in_delta 181.2, Cue.seconds("00:03:01.200")
    cue = Cue.from_h("start_time" => "00:00:01.500", "end_time" => "00:00:04.000", "text" => "Hi")
    assert_equal({ "start_time" => "00:00:01.500", "end_time" => "00:00:04.000", "text" => "Hi" }, cue.to_h)
  end

  def test_talks_come_from_a_checkouts_videos_yml
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "rubykaigi/rubykaigi-2024"))
      File.write(File.join(dir, "rubykaigi/rubykaigi-2024/videos.yml"), <<~YAML)
        - id: "tomoya-ishida-rubykaigi-2024"
          title: "Keynote: Writing Weird Code"
          event_name: "RubyKaigi 2024"
          date: "2024-05-15"
          language: "Japanese"
          slides_url: "https://drive.google.com/file/d/abc/view"
          video_provider: "youtube"
          video_id: "k6QGq5uGhgU"
          speakers:
            - Tomoya Ishida
        - id: "lightning"
          title: "A talk without video"
          video_provider: "not_recorded"
          video_id: "lightning"
      YAML
      catalog = RubyEventsTranscripts::Catalog.new(data_dir: dir)
      talks = catalog.talks("rubykaigi/rubykaigi-2024")
      assert_equal 2, talks.size
      keynote = catalog.talk("rubykaigi/rubykaigi-2024", "k6QGq5uGhgU")
      assert_equal "ja", keynote.language_code
      assert keynote.youtube?
      assert_equal "https://www.rubyevents.org/talks/tomoya-ishida-rubykaigi-2024", keynote.url
      refute talks.last.youtube?
      assert_equal "en", talks.last.language_code
      assert_raises(ArgumentError) { catalog.talks("../etc") }
    end
  end

  def test_rolling_captions_end_where_the_next_one_begins
    rolling = [Cue.new(start: 5.52, finish: 10.8, text: "a"), Cue.new(start: 8.64, finish: 12.9, text: "b"),
               Cue.new(start: 12.88, finish: 14.8, text: "c")]
    untangled = RubyEventsTranscripts::Captions.untangle(rolling)
    assert_equal [[5.52, 8.64], [8.64, 12.88], [12.88, 14.8]], untangled.map { |c| [c.start, c.finish] }
    assert_equal %w[a b c], untangled.map(&:text)
    assert_empty RubyEventsTranscripts::Captions.untangle([])
  end

  def test_the_glossary_has_names_and_the_slides_code
    slides = "IRB IRB Prism Prism.parse ruby_llm Reline Reline the the The RubyVM::InstructionSequence foo irb --type-completor"
    terms = RubyEventsTranscripts::Glossary.build(talk, slides)
    assert_equal "Tomoya Ishida", terms.first
    %w[IRB Prism Prism.parse ruby_llm Reline RubyVM::InstructionSequence --type-completor].each { |term| assert_includes terms, term }
    refute_includes terms, "The"
    refute_includes terms, "foo"
  end

  def test_the_written_json_is_rubyevents_transcript_schema
    Dir.mktmpdir do |dir|
      writer = RubyEventsTranscripts::Writer.new(root: dir)
      cues = [Cue.new(start: 0, finish: 7.5, text: "Hello, RubyKaigi."), Cue.new(start: 8, finish: 15.25, text: "Today: weird code.")]
      path = writer.write(talk, language: "en", cues: cues, meta: { "model" => "fake" })
      assert_equal File.join(dir, "rubykaigi/rubykaigi-2024/k6QGq5uGhgU/en.json"), path
      data = JSON.parse(File.read(path))
      assert_equal %w[cues video_id], data.keys.sort, "nothing beyond the schema"
      assert_equal "k6QGq5uGhgU", data["video_id"]
      data["cues"].each do |cue|
        assert_equal %w[end_time start_time text], cue.keys.sort
        assert_match(/\A\d\d:\d\d:\d\d\.\d{3}\z/, cue["start_time"])
      end
      markdown = File.read(File.join(dir, "rubykaigi/rubykaigi-2024/k6QGq5uGhgU/en.md"))
      assert_includes markdown, "[00:00:08](https://www.youtube.com/watch?v=k6QGq5uGhgU&t=8s) Today: weird code."
      meta = JSON.parse(File.read(File.join(dir, "rubykaigi/rubykaigi-2024/k6QGq5uGhgU/meta.json")))
      assert_equal "fake", meta["en"]["model"]
      assert_equal "Keynote: Writing Weird Code", meta["talk"]["title"]
      assert writer.exist?(talk, "en")
      refute writer.exist?(talk, "ja")
    end
  end
end
