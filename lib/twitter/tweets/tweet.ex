defmodule Twitter.Tweets.Tweet do
  use Ash.Resource,
    otp_app: :twitter,
    domain: Twitter.Tweets,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  attributes do
    uuid_primary_key :id

    attribute :text, :string do
      public? true
    end

    timestamps public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:text]

      change relate_actor(:user)

      validate string_length(:text, max: 255)
    end

    update :update do
      accept [:text]

      validate string_length(:text, max: 255)
    end

    read :feed do
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if always()
    end

    policy action([:update, :destroy]) do
      error_message "only the author can edit or delete a tweet"
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  calculations do
    calculate :text_length, :integer, expr(string_length(text))
    calculate :liked_by_me, :boolean, expr(exists(likes, user_id == ^actor(:id)))
  end

  aggregates do
    count :like_count, :likes do
      public? true
    end

    first :user_email, :user, :email do
      authorize? false
    end

    count :like_count_today, :likes do
      filter expr(inserted_at >= ago(1, :day))
    end

    exists :has_likes, :likes
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

  json_api do
    type "tweet"
    field_names :camelize

    routes do
      base "/tweets"

      index :feed
      get :read, primary?: true
    end
  end
end
