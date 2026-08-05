defmodule Twitter.Tweets.Tweet do
  use Ash.Resource, otp_app: :twitter, domain: Twitter.Tweets, data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id

    attribute :text, :string

    timestamps()
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:text]
    end

    update :update do
      accept [:text]
    end
  end

  postgres do
    table "tweets"
    repo Twitter.Repo
  end
end
