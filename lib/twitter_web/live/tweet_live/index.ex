defmodule TwitterWeb.TweetLive.Index do
  use TwitterWeb, :live_view

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

        <:col :let={{_id, tweet}} label="Length">
          {tweet.text_length}
        </:col>

        <:col :let={{_id, tweet}} label="Author">
          {tweet.user_email}
        </:col>

        <:action :let={{_id, tweet}}>
          <%= if tweet.liked_by_me do %>
            <button phx-click="unlike" phx-value-id={tweet.id}>
              <.icon name="hero-heart-solid" class="text-red-600" />
            </button>
          <% else %>
            <button phx-click="like" phx-value-id={tweet.id}>
              <.icon name="hero-heart" />
            </button>
          <% end %>

          {tweet.like_count}
        </:action>

        <:action :let={{_id, tweet}}>
          <div class="sr-only">
            <.link navigate={~p"/tweets/#{tweet}"}>Show</.link>
          </div>

          <%= if Ash.can?({tweet, :update}, @current_user) do %>
            <.link navigate={~p"/tweets/#{tweet}/edit"}>Edit</.link>
          <% end %>
        </:action>

        <:action :let={{id, tweet}}>
          <%= if Ash.can?({tweet, :destroy}, @current_user) do %>
            <.link
              phx-click={JS.push("delete", value: %{id: tweet.id}) |> hide("##{id}")}
              data-confirm="Are you sure?"
            >
              Delete
            </.link>
          <% end %>
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
       Twitter.Tweets.feed!(actor: socket.assigns.current_user)
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    Twitter.Tweets.delete_tweet!(id, actor: socket.assigns.current_user)

    {:noreply, stream_delete(socket, :tweets, %{id: id})}
  end

  def handle_event("like", %{"id" => tweet_id}, socket) do
    Twitter.Tweets.like!(tweet_id, actor: socket.assigns.current_user)

    {:noreply, refetch_tweet(socket, tweet_id)}
  end

  def handle_event("unlike", %{"id" => tweet_id}, socket) do
    Twitter.Tweets.unlike!(tweet_id, actor: socket.assigns.current_user)

    {:noreply, refetch_tweet(socket, tweet_id)}
  end

  defp refetch_tweet(socket, id) do
    stream_insert(
      socket,
      :tweets,
      Twitter.Tweets.get_tweet!(id, actor: socket.assigns.current_user)
    )
  end
end
