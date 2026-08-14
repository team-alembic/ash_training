defmodule Twitter.Agents do
  use Ash.Domain, otp_app: :twitter, extensions: [AshAi]

  resources do
    resource Twitter.Agents.McpActions
  end

  tools do
    tool :ash_lua_docs, Twitter.Agents.McpActions, :docs do
      description "Read the docs for the Lua API: which tweet, like and user actions a script can call, and how."
    end

    tool :ash_lua_eval, Twitter.Agents.McpActions, :eval do
      description "Run a Lua script against that API. Use it for questions that need several queries, filtering or arithmetic, and get the final answer in one call."
    end
  end
end
