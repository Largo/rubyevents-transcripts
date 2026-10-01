# frozen_string_literal: true

# An app, not a gem: there is no gemspec on purpose, so no gem name for
# anybody to take on rubygems.org in our place. Should this become a gem one
# day, register the name with the first real release.
source "https://rubygems.org"

ruby ">= 3.2"

gem "pdf-reader", ">= 2.12"
gem "ruby_llm", ">= 1.15"
gem "youtube-transcript-rb", ">= 0.1"

group :development, :test do
  gem "minitest"
  gem "rake"
end

# Optional gems for this machine only (gitignored) - e.g. your Claude Code
# login as a RubyLLM provider (PROVIDER=claude_cli, no API key needed):
#   gem "ruby_llm-claude_cli"                               # from rubygems
#   gem "ruby_llm-claude_cli", path: "../ruby_llm-claude_cli"   # a checkout
eval_gemfile "Gemfile.local" if File.exist?(File.join(__dir__, "Gemfile.local"))
