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
      accept [:text, :user_id]
    end

    update :update do
      accept [:text]
    end
  end

  postgres do
    table "tweets"
    repo Twitter.Repo
  end

  relationships do
    belongs_to :user, Twitter.Accounts.User do
      allow_nil? false
    end

    has_many :likes, Twitter.Tweets.Like

    has_many :likers, Twitter.Accounts.User do
      through [:likes, :user]
    end
  end
end
