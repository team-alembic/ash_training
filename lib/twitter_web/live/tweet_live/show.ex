defmodule TwitterWeb.TweetLive.Show do
  use TwitterWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Tweet {@tweet.id}
        <:subtitle>This is a tweet record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/tweets/#{@tweet}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit tweet
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Text">{@tweet.text}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:tweet, Ash.get!(Twitter.Tweets.Tweet, id, actor: socket.assigns.current_user))}
  end

  defp page_title(:show), do: "Show Tweet"
end
