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

      <.form for={@form} id="tweet-form" phx-submit="save" phx-change="validate">
        <.input label="Text" type="textarea" field={@form[:text]} />
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
    tweet = Twitter.Tweets.get_tweet!(id, actor: socket.assigns.current_user)

    if Ash.can?({tweet, :update}, socket.assigns.current_user) do
      socket
      |> assign(:page_title, "Edit Tweet")
      |> assign(:tweet, tweet)
      |> assign_form()
    else
      socket
      |> assign(:page_title, "Edit Tweet")
      |> assign(:tweet, tweet)
      |> assign_form()
      |> put_flash(:error, "You are not allowed to edit this tweet.")
      |> push_navigate(to: ~p"/tweets/#{tweet}")
    end
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Tweet")
    |> assign(:tweet, nil)
    |> assign_form()
  end

  @impl true
  def handle_event("save", %{"tweet" => tweet_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: tweet_params) do
      {:ok, _tweet} ->
        socket =
          socket
          |> put_flash(:info, "Tweet #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: ~p"/")

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("validate", %{"tweet" => tweet_params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, tweet_params))}
  end

  defp assign_form(%{assigns: %{tweet: tweet}} = socket) do
    form =
      if tweet do
        Twitter.Tweets.form_to_update_tweet(tweet,
          as: "tweet",
          actor: socket.assigns.current_user
        )
      else
        Twitter.Tweets.form_to_create_tweet(
          as: "tweet",
          actor: socket.assigns.current_user
        )
      end

    assign(socket, form: to_form(form))
  end
end
