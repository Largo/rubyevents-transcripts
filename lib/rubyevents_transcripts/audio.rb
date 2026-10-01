# frozen_string_literal: true

require "fileutils"
require "open3"

module RubyEventsTranscripts
  # Experimental: cues from the talk's audio instead of YouTube's captions -
  # for talks without captions, or whose automatic ones are poor (often the
  # case for Japanese). yt-dlp (and ffmpeg) fetch the audio as small mono
  # MP3 (32 kbit/s: an hour is about 14 MB, under OpenAI's 25 MB limit);
  # RubyLLM.transcribe turns it into timed segments, with the glossary as
  # the recogniser's vocabulary. whisper-1 returns segments; check what
  # another model returns before relying on it.
  class Audio
    def initialize(cache_dir: "cache", model: "whisper-1", provider: nil)
      @cache_dir = cache_dir
      @model = model
      @provider = provider
    end

    def cues(talk, glossary: [])
      raise ArgumentError, "#{talk.id}: audio needs a YouTube video" unless talk.youtube?

      path = download(talk)
      options = { model: @model, language: talk.language_code, prompt: glossary.first(60).join(", "),
                  format: "verbose_json", timestamps: :segment }
      options.merge!(provider: @provider.to_sym, assume_model_exists: true) if @provider
      transcription = RubyLLM.transcribe(path, **options)
      segments = Array(transcription.segments)
      raise "#{@model} returned no timed segments" if segments.empty?

      segments.map do |segment|
        value = ->(key) { segment[key] || segment[key.to_s] }
        Cue.new(start: value.(:start).to_f, finish: value.(:end).to_f, text: value.(:text).to_s.strip)
      end
    end

    private

    def download(talk)
      dir = File.join(@cache_dir, talk.video_id)
      path = File.join(dir, "audio.mp3")
      return path if File.exist?(path)

      FileUtils.mkdir_p(dir)
      command = ["yt-dlp", "--no-playlist", "-x", "--audio-format", "mp3", "--postprocessor-args", "ffmpeg:-ac 1 -b:a 32k",
                 "-o", File.join(dir, "audio.%(ext)s"), "https://www.youtube.com/watch?v=#{talk.video_id}"]
      _output, status = Open3.capture2e(*command)
      raise "yt-dlp could not fetch the audio of #{talk.video_id}" unless status.success? && File.exist?(path)

      path
    rescue Errno::ENOENT
      raise "audio needs yt-dlp and ffmpeg on the PATH"
    end
  end
end
