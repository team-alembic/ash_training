defmodule Twitter.Agents.McpActions do
  use Ash.Resource,
    domain: Twitter.Agents,
    extensions: [AshLua.EvalActions]

  eval_actions do
    resource Twitter.Tweets.Tweet, actions: [:read, :feed, :create, :semantic_search]
    resource Twitter.Tweets.Like, actions: [:read, :like, :unlike]
    resource Twitter.Accounts.User, actions: [:read]
  end
end
