# frozen_string_literal: true

require "net/http"
require "uri"
require "yaml"

module RubyEventsTranscripts
  # The talks of one event, from RubyEvents.org's data: a local checkout of
  # github.com/rubyevents/rubyevents (data_dir), or that repository on GitHub.
  #
  #   Catalog.new.talks("rubykaigi/rubykaigi-2024")
  class Catalog
    RAW = "https://raw.githubusercontent.com/rubyevents/rubyevents/main/data"

    def initialize(data_dir: ENV.fetch("RUBYEVENTS_DATA", nil))
      @data_dir = data_dir
    end

    # every talk of +event_path+ ("series/event"), in the file's order
    def talks(event_path)
      entries = YAML.safe_load(videos_yml(event_path), permitted_classes: [Date, Time], aliases: true) || []
      entries.map { |entry| Talk.from_yaml(event_path, entry) }
    end

    # the talk with this RubyEvents id (or YouTube video id)
    def talk(event_path, id)
      talks(event_path).find { |talk| talk.id == id || talk.video_id == id } or
        raise ArgumentError, "no talk #{id.inspect} in #{event_path}"
    end

    private

    def videos_yml(event_path)
      raise ArgumentError, "an event is series/event, like rubykaigi/rubykaigi-2024" unless event_path.match?(%r{\A[\w-]+/[\w-]+\z})
      return File.read(File.join(@data_dir, event_path, "videos.yml"), encoding: "UTF-8") if @data_dir

      response = Net::HTTP.get_response(URI("#{RAW}/#{event_path}/videos.yml"))
      raise ArgumentError, "#{event_path}: no videos.yml on GitHub (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

      response.body.force_encoding(Encoding::UTF_8)
    end
  end
end
