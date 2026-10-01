# frozen_string_literal: true

module RubyEventsTranscripts
  # A stretch of a talk and what is said in it: a caption line from YouTube,
  # or a finished paragraph. Times are seconds; RubyEvents.org writes them as
  # "HH:MM:SS.mmm" (its TranscriptSchema).
  Cue = Data.define(:start, :finish, :text) do
    def self.from_h(hash)
      new(start: Cue.seconds(hash.fetch("start_time")), finish: Cue.seconds(hash.fetch("end_time")),
          text: hash.fetch("text"))
    end

    # "00:03:01.200" -> 181.2
    def self.seconds(stamp)
      hours, minutes, seconds = stamp.to_s.split(":")
      (hours.to_i * 3600) + (minutes.to_i * 60) + seconds.to_f
    end

    # 181.2 -> "00:03:01.200"
    def self.stamp(seconds)
      millis = (seconds.to_f * 1000).round
      format("%02d:%02d:%02d.%03d", millis / 3_600_000, millis / 60_000 % 60, millis / 1000 % 60, millis % 1000)
    end

    def to_h = { "start_time" => Cue.stamp(start), "end_time" => Cue.stamp(finish), "text" => text }
    def duration = finish - start
  end
end
