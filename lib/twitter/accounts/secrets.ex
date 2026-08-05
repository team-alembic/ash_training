defmodule Twitter.Accounts.Secrets do
  @moduledoc "Secrets adapter for Twitter authentication"
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], Twitter.Accounts.User, _, _) do
    Application.fetch_env(:twitter, :token_signing_secret)
  end
end
