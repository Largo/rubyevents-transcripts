# frozen_string_literal: true

module RubyEventsTranscripts
  # A talk as RubyEvents.org's data/<series>/<event>/videos.yml describes it.
  Talk = Data.define(:event_path, :id, :title, :speakers, :event_name, :date, :language,
                     :video_provider, :video_id, :slides_url, :description) do
    # videos.yml names languages ("Japanese"); captions and the schema use codes
    LANGUAGE_CODES = {
      "english" => "en", "japanese" => "ja", "spanish" => "es", "portuguese" => "pt", "french" => "fr",
      "german" => "de", "italian" => "it", "russian" => "ru", "chinese" => "zh", "korean" => "ko",
      "polish" => "pl", "dutch" => "nl", "ukrainian" => "uk", "turkish" => "tr", "bulgarian" => "bg",
      "czech" => "cs", "hungarian" => "hu", "finnish" => "fi", "swedish" => "sv", "norwegian" => "no",
      "danish" => "da", "greek" => "el", "romanian" => "ro", "hebrew" => "he", "indonesian" => "id",
      "vietnamese" => "vi", "thai" => "th", "lithuanian" => "lt", "latvian" => "lv", "estonian" => "et",
      "serbian" => "sr", "croatian" => "hr", "slovak" => "sk", "slovenian" => "sl", "catalan" => "ca"
    }.freeze

    def self.from_yaml(event_path, entry)
      new(event_path: event_path, id: entry["id"].to_s, title: entry["title"].to_s,
          speakers: Array(entry["speakers"]).map(&:to_s), event_name: entry["event_name"].to_s,
          date: entry["date"].to_s, language: entry["language"].to_s, video_provider: entry["video_provider"].to_s,
          video_id: entry["video_id"].to_s, slides_url: entry["slides_url"], description: entry["description"].to_s)
    end

    # "ja" for "Japanese"; a code stays a code; English when unknown
    def language_code
      name = language.strip.downcase
      return "en" if name.empty?

      LANGUAGE_CODES.fetch(name) { name.length.between?(2, 3) ? name : "en" }
    end

    def youtube? = video_provider == "youtube" && !video_id.empty?
    def url = "https://www.rubyevents.org/talks/#{id}"
  end
end
