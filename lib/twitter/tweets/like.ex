defmodule Twitter.Tweets.Like do
  use Ash.Resource,
    otp_app: :twitter,
    domain: Twitter.Tweets,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshLua.Resource]

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

    create :like do
      accept [:tweet_id]

      change relate_actor(:user)

      upsert? true
      upsert_identity :unique_user_tweet
    end

    destroy :unlike do
      argument :tweet_id, :uuid, allow_nil?: false

      change filter(expr(tweet_id == ^arg(:tweet_id) and user_id == ^actor(:id)))
    end

    action :liked?, :boolean do
      argument :tweet_id, :uuid, allow_nil?: false

      run fn input, context ->
        require Ash.Query

        Twitter.Tweets.Like
        |> Ash.Query.filter(
          tweet_id == ^input.arguments.tweet_id and user_id == ^context.actor.id
        )
        |> Ash.exists(Ash.Context.to_opts(context))
      end
    end
  end

  identities do
    identity :unique_user_tweet, [:user_id, :tweet_id]
  end

  postgres do
    table "likes"
    repo Twitter.Repo

    references do
      reference :tweet, on_delete: :delete, index?: true
    end
  end
end
