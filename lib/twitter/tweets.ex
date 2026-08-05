defmodule Twitter.Tweets do
  use Ash.Domain,
    otp_app: :twitter,
    extensions: [
      AshGraphql.Domain,
      AshJsonApi.Domain,
      AshAdmin.Domain,
      AshPhoenix,
      AshAi,
      AshLua.Domain
    ]

  admin do
    show? true
  end

  json_api do
    prefix "/api/json"
  end

  lua do
    namespace "tweets" do
      action :feed, Twitter.Tweets.Tweet, :feed, labels: [:agent, :read_only]
      action :list, Twitter.Tweets.Tweet, :read, labels: [:agent, :read_only]
      action :search, Twitter.Tweets.Tweet, :semantic_search, labels: [:agent, :read_only]
      action :create, Twitter.Tweets.Tweet, :create, labels: [:agent]
    end

    namespace "likes" do
      action :list, Twitter.Tweets.Like, :read, labels: [:agent, :read_only]
      action :like, Twitter.Tweets.Like, :like, labels: [:agent]
      action :unlike, Twitter.Tweets.Like, :unlike, labels: [:agent]
    end
  end

  resources do
    resource Twitter.Tweets.Tweet do
      define :feed,
        default_options: [load: [:text_length, :liked_by_me, :like_count, :user_email]]

      define :get_tweet,
        action: :read,
        get_by: [:id],
        default_options: [load: [:text_length, :liked_by_me, :like_count, :user_email]]

      define :delete_tweet, action: :destroy

      define :create_tweet, action: :create
      define :update_tweet, action: :update
      define :ask, action: :ask, args: [:question]
    end

    resource Twitter.Tweets.Like do
      define :like, args: [:tweet_id]
      define :unlike, args: [:tweet_id], require_reference?: false
      define :liked?, args: [:tweet_id]
    end
  end

  tools do
    tool :read_feed, Twitter.Tweets.Tweet, :feed do
      description "Retrieve the feed of tweets. Returns a list of tweets with their text, user email, and like count."

      # Load calculations/aggregates/relationships into the tool's response
      load [:user_email, :like_count]

      # Run synchronously instead of the default async execution
      async false
    end

    tool :read_tweet, Twitter.Tweets.Tweet, :read do
      description "Retrieve a list of tweets, also supports filtering, sorting, and more"
    end

    tool :semantic_search_tweets, Twitter.Tweets.Tweet, :semantic_search do
      description "Perform a semantic search over tweets based on a query string"
    end

    tool :create_tweet, Twitter.Tweets.Tweet, :create

    tool :like_tweet, Twitter.Tweets.Like, :like

    tool :unlike_tweet, Twitter.Tweets.Like, :unlike do
      identity false
    end
  end
end
