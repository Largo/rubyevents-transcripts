# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module RubyEventsTranscripts
  # transcripts/<series>/<event>/<video_id>/
  #   <lang>.json   RubyEvents.org's TranscriptSchema: {video_id, cues: [{start_time, end_time, text}]}
  #   <lang>.md     the same to read and review, timestamps linking into the video
  #   meta.json     per language: where it came from, which model, how it went
  class Writer
    def initialize(root: "transcripts")
      @root = root
    end

    def dir(talk) = File.join(@root, talk.event_path, talk.video_id)

    def exist?(talk, language) = File.exist?(File.join(dir(talk), "#{language}.json"))

    def write(talk, language:, cues:, meta:)
      folder = dir(talk)
      FileUtils.mkdir_p(folder)
      json = File.join(folder, "#{language}.json")
      File.write(json, "#{JSON.pretty_generate('video_id' => talk.video_id, 'cues' => cues.map(&:to_h))}\n")
      File.write(File.join(folder, "#{language}.md"), markdown(talk, cues))
      metas = File.exist?(meta_path = File.join(folder, "meta.json")) ? JSON.parse(File.read(meta_path)) : {}
      metas["talk"] = { "id" => talk.id, "title" => talk.title, "speakers" => talk.speakers, "url" => talk.url }
      metas[language] = meta.merge("generated_at" => Time.now.utc.iso8601, "tool" => "rubyevents_transcripts #{VERSION}")
      File.write(meta_path, "#{JSON.pretty_generate(metas)}\n")
      json
    end

    private

    def markdown(talk, cues)
      lines = ["# #{talk.title}", "", "#{talk.speakers.join(', ')} · #{talk.event_name} · #{talk.url}", ""]
      cues.each do |cue|
        link = talk.youtube? ? "https://www.youtube.com/watch?v=#{talk.video_id}&t=#{cue.start.floor}s" : nil
        stamp = Cue.stamp(cue.start)[0, 8]
        lines << "#{link ? "[#{stamp}](#{link})" : stamp} #{cue.text}" << ""
      end
      lines.join("\n")
    end
  end
end
