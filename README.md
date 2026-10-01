# rubyevents-transcripts

Readable, correctly timed transcripts for the talks on
[RubyEvents.org](https://www.rubyevents.org) - in the talk's language and,
for a talk that isn't in English, in English too.

A talk's automatic YouTube captions go in: lines like
`ますそれではwiingWC奇妙なコード`. Out come paragraphs ("それでは「Writing
Weird Code」、奇妙なコードを書くということについて…") that keep the captions'
own timings, with names, Ruby terms and code spelled the way the talk's
slides spell them. The language work is done by [RubyLLM](https://rubyllm.com),
with any provider it supports - or, with
[ruby_llm-claude_cli](https://github.com/Largo/ruby_llm-claude_cli), through
your Claude Code login, no API key needed.

The files it writes are in RubyEvents.org's own transcript format
(`TranscriptSchema`: `{video_id, cues: [{start_time, end_time, text}]}`), so
they can go into the site as they are. Why this is a repository of its own
for now, and how it could get into RubyEvents.org: [docs/UPSTREAM.md](docs/UPSTREAM.md).

## Use

```sh
bundle install
bundle exec bin/transcribe list rubykaigi/rubykaigi-2024        # the event's talks
bundle exec bin/transcribe talk rubykaigi/rubykaigi-2024 tomoya-ishida-rubykaigi-2024 \
  --model gpt-5-mini --minutes 5                                # a trial: the first 5 minutes
bundle exec bin/transcribe event rubykaigi/rubykaigi-2024 --model gpt-5-mini   # every talk, skipping done ones
```

Events are named as in RubyEvents.org's `data/` directory (`series/event`);
the talk list comes from GitHub, or from a checkout with `--data
path/to/rubyevents/data`. A talk is named by its RubyEvents id or YouTube
video id.

| Option | |
|---|---|
| `--model`, `--provider` | any RubyLLM model and provider (or `TRANSCRIPTS_MODEL`, `TRANSCRIPTS_PROVIDER`); keys from `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, ... |
| `--languages ja,en` | which transcripts to write (default: the talk's language, plus English) |
| `--slides PATH_OR_URL` | slides to use instead of the talk's `slides_url` (Google Drive, Speaker Deck, a PDF link or a local file) |
| `--minutes N` | only the first N minutes |
| `--source audio` | experimental: the talk's audio instead of its captions (below) |
| `--out DIR`, `--force` | where to write (default `transcripts/`), and whether to write over existing ones |

### Through your Claude Code login

[ruby_llm-claude_cli](https://github.com/Largo/ruby_llm-claude_cli) runs the
chats through `claude -p`. Add it for this machine only, in a gitignored
`Gemfile.local`:

```ruby
gem "ruby_llm-claude_cli"                                   # or: path: "../ruby_llm-claude_cli"
```

```sh
bundle install
bundle exec bin/transcribe talk rubykaigi/rubykaigi-2024 k6QGq5uGhgU --provider claude_cli --model sonnet
```

### From the audio (experimental)

For talks without captions, or with poor ones: `--source audio` fetches the
audio with [yt-dlp](https://github.com/yt-dlp/yt-dlp) (and ffmpeg) as small
mono MP3 and transcribes it with `RubyLLM.transcribe` (`whisper-1` by
default, which returns timed segments; needs `OPENAI_API_KEY`), the slides'
vocabulary as the recogniser's prompt. Not tried against a real talk yet.

## What comes out

```
transcripts/<series>/<event>/<video_id>/
  ja.json, en.json   RubyEvents.org's TranscriptSchema
  ja.md, en.md       the same to read and review; each timestamp links into the video
  meta.json          per language: source, model, provider, translated, chunks, fallbacks
```

The first one: Tomoya Ishida's RubyKaigi 2024 keynote "Writing Weird Code",
spoken in Japanese - [Japanese](transcripts/rubykaigi/rubykaigi-2024/k6QGq5uGhgU/ja.md)
and [English](transcripts/rubykaigi/rubykaigi-2024/k6QGq5uGhgU/en.md), 51
minutes in 13 chunks each, from YouTube's automatic Japanese captions and the
slides, with `sonnet` through ruby_llm-claude_cli.

## How it works

- **Captions**: the talk's YouTube captions through
  [youtube-transcript-rb](https://rubygems.org/gems/youtube-transcript-rb), the
  gem RubyEvents.org uses, cached in `cache/`. Automatic captions roll -
  each line stays up after the next appears - so every line is cut where the
  next begins.
- **Glossary**: the speakers, the event and the terms of the slides
  (`pdftotext` when installed, pdf-reader otherwise) - code (`Prism.parse`,
  `ruby_llm`, `--type-completor`), CamelCase, acronyms and words that come
  back - so "TomPNG" becomes tompng and "wiingWC" Writing Weird Code.
- **Paragraphs with the captions' timings**: the talk goes in chunks of
  about four minutes. The model gets numbered caption lines and answers
  which line numbers form a paragraph, and its text - never a timestamp. A
  paragraph runs from its first line's start to its last line's end.
- **Nothing left out**: every line of a chunk has to be in exactly one
  paragraph, in order. An answer that skips or repeats lines is asked
  again, with what was wrong; after that, the chunk keeps its raw lines
  (`fallback_chunks` in `meta.json`).
- **Translation**: for the English transcript of a Japanese talk the same
  happens, with the model translating as it edits - same paragraphs, same
  timings.

## Tests

```sh
bundle exec rake test     # no network, no model: a fake chat
```

## Licence

The code: MIT. The transcripts are the speakers' words, written down for
RubyEvents.org; a speaker who does not want theirs here gets it removed.
