defmodule Twitter.Agents do
  use Ash.Domain, otp_app: :twitter, extensions: [AshAi]

  resources do
    resource Twitter.Agents.McpActions
  end

  tools do
    tool :ash_lua_docs, Twitter.Agents.McpActions, :docs
    tool :ash_lua_eval, Twitter.Agents.McpActions, :eval
  end
end
