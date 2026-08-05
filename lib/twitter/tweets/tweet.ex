defmodule Twitter.Tweets.Tweet do
  use Ash.Resource, otp_app: :twitter, domain: Twitter.Tweets, data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  actions do
    defaults [:read, :destroy]
  end

  postgres do
    table "tweets"
    repo Twitter.Repo
  end
end
