defmodule Twitter.Tweets.Like do
  use Ash.Resource, otp_app: :twitter, domain: Twitter.Tweets, data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :tweet, Twitter.Tweets.Tweet do
      allow_nil? false
    end

    belongs_to :user, Twitter.Accounts.User do
      allow_nil? false
    end
  end

  actions do
    defaults [:read]
  end

  postgres do
    table "likes"
    repo Twitter.Repo
  end
end
