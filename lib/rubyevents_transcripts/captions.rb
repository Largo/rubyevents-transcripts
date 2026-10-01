# frozen_string_literal: true

require "json"
require "fileutils"
require "youtube-transcript-rb"

module RubyEventsTranscripts
  # A talk's YouTube captions as cues - the same source RubyEvents.org uses
  # (youtube-transcript-rb), cached under cache/<video_id>/ so a second run
  # asks YouTube nothing.
  class Captions
    Track = Data.define(:language, :generated, :cues)

    def initialize(cache_dir: "cache")
      @cache_dir = cache_dir
    end

    # the talk's own language first, then English; nil when YouTube has none
    def fetch(talk, languages: [talk.language_code, "en"].uniq)
      cached = File.join(@cache_dir, talk.video_id, "captions.json")
      return load(cached) if File.exist?(cached)

      fetched = YoutubeRb::Transcript::YouTubeTranscriptApi.new.fetch(talk.video_id, languages: languages)
      cues = fetched.snippets.map { |s| Cue.new(start: s.start, finish: s.start + s.duration, text: clean(s.text)) }
      track = Track.new(language: fetched.language_code, generated: fetched.is_generated, cues: self.class.untangle(cues))
      save(cached, track)
      track
    rescue YoutubeRb::Transcript::CouldNotRetrieveTranscript
      nil
    end

    # Automatic captions roll: each line stays up until after the next one
    # appears. A line ends where the next begins, so paragraphs built from
    # them do not overlap either.
    def self.untangle(cues)
      cues.each_cons(2).map { |cue, following| following.start > cue.start ? cue.with(finish: [cue.finish, following.start].min) : cue }
          .push(*cues.last(1))
    end

    private

    # "&gt;&gt; so um" -> ">> so um"; line breaks inside a caption are spaces
    def clean(text)
      text.to_s.gsub("&amp;", "&").gsub("&gt;", ">").gsub("&lt;", "<").gsub("&#39;", "'")
          .gsub("&quot;", '"').gsub(/\s+/, " ").strip
    end

    def save(path, track)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate("language" => track.language, "generated" => track.generated,
                                            "cues" => track.cues.map(&:to_h)))
    end

    def load(path)
      data = JSON.parse(File.read(path, encoding: "UTF-8"))
      Track.new(language: data["language"], generated: data["generated"],
                cues: self.class.untangle(data["cues"].map { |c| Cue.from_h(c) }))
    end
  end
end
