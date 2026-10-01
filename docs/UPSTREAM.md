# Into RubyEvents.org

## Where RubyEvents.org is (October 2026)

- Transcripts live in the database, per language (`talk_transcripts`:
  `raw_transcript`, `enhanced_transcript`, `language`, `auto_generated`,
  `translated`) - since
  [#1862](https://github.com/rubyevents/rubyevents/pull/1862) (July 2026),
  which also removed the earlier `data/**/transcripts.yml` files and their
  rake tasks ([#1209](https://github.com/rubyevents/rubyevents/pull/1209),
  January 2026). `app/schemas/transcript_schema.rb` still describes that
  file format.
- Raw transcripts are YouTube's captions, fetched by
  `Talk::YouTubeTranscript` (youtube-transcript-rb) and backfilled by a
  recurring job ([#1877](https://github.com/rubyevents/rubyevents/pull/1877)).
- `Talk::Agents#improve_transcript` sends a talk's whole VTT to
  `gpt-5-mini` in one request (`Prompts::Talk::EnhanceTranscript`) and has
  the model write paragraphs with their own timestamps.
- [#452 "Transcript talks"](https://github.com/rubyevents/rubyevents/issues/452)
  is open. Its points: YouTube's raw captions are poor; the OpenAI pass is
  better but "sometimes incomplete and the timings are often wrong"; could
  transcripts be made locally and seeded in production; could the
  transcriber get the talk's technical terms as context?
- RubyEvents.org already depends on `ruby_llm` (1.15).

## Why a repository of its own, for now

- RubyEvents.org decided three months ago to keep transcripts out of
  `data/`. Committing them there again is the maintainers' call, not
  something to slip into a tooling PR.
- The parts that make transcripts good are offline work: slide PDFs, a
  glossary, optionally the audio (yt-dlp, ffmpeg, a speech model), and the
  choice of model - on someone's own API key or Claude subscription
  (ruby_llm-claude_cli), not on the site's servers and budget.
- Quality needs iterating - prompts, models, chunk sizes - on real talks.
  That is quicker here, with reviewable output (`<lang>.md`), than in the
  site's PR queue.

Nothing here depends on that choice: the output is the site's own cue
format, and the enhancer uses only RubyLLM calls that 1.15 has too
(`RubyLLM.chat`, `with_instructions`, `with_schema`, `ask`).

## The way in

1. **Show it on #452**: a few talks done end to end - a Japanese one with
   its English track, an English one - next to what the site shows now. A
   draft comment is below.
2. **An import**, if the maintainers want these transcripts: a small change
   in RubyEvents.org that reads `<lang>.json` from this repository (or a
   release of it) into `talk_transcripts.enhanced_transcript`, keyed by
   `video_id` and language, `translated` from `meta.json`. As a rake task,
   roughly:

   ```ruby
   # lib/tasks/external_transcripts.rake (sketch)
   task "transcripts:import_external", [:dir] => :environment do |_t, args|
     Dir[File.join(args[:dir], "**/meta.json")].each do |meta_path|
       folder = File.dirname(meta_path)
       talk = Talk.find_by(video_id: File.basename(folder)) or next
       meta = JSON.parse(File.read(meta_path))
       (meta.keys - ["talk"]).each do |language|
         cues = JSON.parse(File.read(File.join(folder, "#{language}.json")))["cues"]
         transcript = talk.talk_transcripts.find_or_initialize_by(language: language)
         transcript.update!(enhanced_transcript: Talk::Transcript::CueList.from_json(cues),
                            translated: meta.dig(language, "translated"))
       end
     end
   end
   ```

3. **The enhancer in the site**, if they would rather keep generating there:
   the chunked, line-number based approach (lib/rubyevents_transcripts/enhancer.rb)
   can replace the one-request prompt in `Talk::Agents#improve_transcript` -
   it addresses exactly the incomplete answers and wrong timings of #452,
   and takes the slides' terms as context.

## Draft comment for #452

> Picking this up: I built a small tool that turns a talk's YouTube captions
> into paragraphs - in the talk's language, plus an English track for
> non-English talks - and writes RubyEvents' own cue format
> (`{video_id, cues: [{start_time, end_time, text}]}`).
>
> On the two problems from this thread:
>
> - **Timings**: the model never writes a timestamp. It gets numbered
>   caption lines and answers which numbers form a paragraph; the paragraph
>   runs from its first line's start to its last line's end. (Auto captions
>   overlap, so each line is first cut where the next begins.)
> - **Incomplete output**: the talk goes in ~4-minute chunks, and every line
>   must land in exactly one paragraph, in order - otherwise the chunk is
>   asked again, and after that keeps its raw lines.
>
> For technical terms, it builds a glossary from the slides (`slides_url`)
> and the talk's metadata, so "wiingWC" becomes "Writing Weird Code" and
> "TomPNG" becomes tompng. It runs on RubyLLM, so any provider works.
>
> Examples: [links]. Would you want transcripts like these on the site? I can
> open a PR for an import (rake task or Avo action), or port the enhancer
> into `Talk::Agents#improve_transcript` - whichever fits better.
