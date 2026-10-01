# frozen_string_literal: true

require "ruby_llm"

module RubyEventsTranscripts
  # RubyLLM, configured from the environment. Any provider RubyLLM knows
  # works (OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY, ...); with
  # provider "claude_cli" and the ruby_llm-claude_cli gem, chats run through
  # the local Claude Code login instead of an API key.
  module LLM
    KEYS = { openai_api_key: "OPENAI_API_KEY", anthropic_api_key: "ANTHROPIC_API_KEY",
             gemini_api_key: "GEMINI_API_KEY", deepseek_api_key: "DEEPSEEK_API_KEY",
             openrouter_api_key: "OPENROUTER_API_KEY", ollama_api_base: "OLLAMA_API_BASE" }.freeze

    module_function

    def configure!
      RubyLLM.configure do |config|
        KEYS.each { |setting, env| config.public_send("#{setting}=", ENV[env]) if ENV[env] && config.respond_to?("#{setting}=") }
      end
    end

    # A fresh chat for one request; +provider+ nil lets RubyLLM pick by model.
    def chat(model:, provider: nil)
      require_provider(provider)
      return RubyLLM.chat(model: model) unless provider

      RubyLLM.chat(model: model, provider: provider.to_sym, assume_model_exists: true)
    end

    def require_provider(provider)
      return unless provider.to_s == "claude_cli"

      require "ruby_llm/claude_cli"
    rescue LoadError
      raise LoadError, "provider claude_cli needs the ruby_llm-claude_cli gem (see Gemfile: Gemfile.local)"
    end
  end
end
