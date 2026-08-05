defmodule TwitterWeb.TweetLive.Index do
  use TwitterWeb, :live_view

  @tweet_loads [user: [:email]]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Tweets
        <:actions>
          <.button variant="primary" navigate={~p"/tweets/new"}>
            <.icon name="hero-plus" /> New Tweet
          </.button>
        </:actions>
      </.header>

      <.table
        id="tweets"
        rows={@streams.tweets}
        row_click={fn {_id, tweet} -> JS.navigate(~p"/tweets/#{tweet}") end}
      >
        <:col :let={{_id, tweet}} label="Id">
          <span class="max-w-24 text-wrap">
            {tweet.id}
          </span>
        </:col>

        <:col :let={{_id, tweet}} label="Text">
          {tweet.text}
        </:col>

        <:col :let={{_id, tweet}} label="Author">
          {tweet.user.email}
        </:col>

        <:action :let={{_id, tweet}}>
          <button phx-click="like" phx-value-id={tweet.id}>
            <.icon name="hero-arrow-up" />
          </button>
          <button phx-click="unlike" phx-value-id={tweet.id}>
            <.icon name="hero-arrow-down" />
          </button>
        </:action>

        <:action :let={{_id, tweet}}>
          <div class="sr-only">
            <.link navigate={~p"/tweets/#{tweet}"}>Show</.link>
          </div>

          <.link navigate={~p"/tweets/#{tweet}/edit"}>Edit</.link>
        </:action>

        <:action :let={{id, tweet}}>
          <.link
            phx-click={JS.push("delete", value: %{id: tweet.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Tweets")
     |> stream(
       :tweets,
       Ash.read!(Twitter.Tweets.Tweet,
         actor: socket.assigns.current_user,
         action: :feed,
         load: @tweet_loads
       )
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    Twitter.Tweets.Tweet
    |> Ash.get!(id, action: :read)
    |> Ash.Changeset.for_destroy(:destroy, %{}, actor: socket.assigns.current_user)
    |> Ash.destroy!()

    {:noreply, stream_delete(socket, :tweets, %{id: id})}
  end

  def handle_event("like", %{"id" => tweet_id}, socket) do
    Twitter.Tweets.Like
    |> Ash.Changeset.for_create(:like, %{tweet_id: tweet_id}, actor: socket.assigns.current_user)
    |> Ash.create!()

    {:noreply, refetch_tweet(socket, tweet_id)}
  end

  def handle_event("unlike", %{"id" => tweet_id}, socket) do
    Ash.bulk_destroy!(
      Twitter.Tweets.Like,
      :unlike,
      %{tweet_id: tweet_id},
      actor: socket.assigns.current_user
    )

    {:noreply, refetch_tweet(socket, tweet_id)}
  end

  defp refetch_tweet(socket, id) do
    stream_insert(
      socket,
      :tweets,
      Ash.get!(Twitter.Tweets.Tweet, id, actor: socket.assigns.current_user, load: @tweet_loads)
    )
  end
end
