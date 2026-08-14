defmodule Twitter.Accounts.Secrets do
  @moduledoc "Secrets adapter for Twitter authentication"
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], Twitter.Accounts.User, _, _) do
    Application.fetch_env(:twitter, :token_signing_secret)
  end

  def secret_for([:issuer_url], Twitter.Oauth2Server, _opts, _context) do
    Application.fetch_env(:twitter, :oauth2_issuer_url)
  end

  def secret_for([:resource_url], Twitter.Oauth2Server, _opts, _context) do
    Application.fetch_env(:twitter, :oauth2_resource_url)
  end

  def secret_for([:signing_secret], Twitter.Oauth2Server, _opts, _context) do
    Application.fetch_env(:twitter, :oauth2_signing_secret)
  end
end
