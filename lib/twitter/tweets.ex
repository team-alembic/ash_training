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
    end

    resource Twitter.Tweets.Like do
      define :like, args: [:tweet_id]
      define :unlike, args: [:tweet_id], require_reference?: false
      define :liked?, args: [:tweet_id]
    end
  end

  tools do
    tool :read_feed, Twitter.Tweets.Tweet, :feed
  end
end
