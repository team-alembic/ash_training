defmodule TwitterWeb.TweetLive.Form do
  use TwitterWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage tweet records in your database.</:subtitle>
      </.header>

      <.form for={%{}} as={:tweet} id="tweet-form" phx-submit="save">
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Tweet</.button>
          <.button navigate={~p"/"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Tweet")
    |> assign(
      :tweet,
      Ash.get!(Twitter.Tweets.Tweet, id, actor: socket.assigns.current_user)
    )
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Tweet")
    |> assign(:tweet, nil)
  end

  @impl true
  def handle_event("save", params, socket) do
    result =
      if socket.assigns.tweet do
        # we're updating a tweet. Update logic goes here.
        {:error, "Update not implemented"}
      else
        # we're creating a tweet. Create logic goes here.
        {:error, "Create not implemented"}
      end

    case result do
      {:ok, _tweet} ->
        socket =
          socket
          |> put_flash(:info, "Success!")
          |> push_navigate(to: ~p"/")

        {:noreply, socket}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Error!: #{Exception.format(:error, error)}")}
    end
  end
end
