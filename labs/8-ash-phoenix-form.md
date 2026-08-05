# Lab 8 - `AshPhoenix.Form`

## Relevant Documentation

- [AshPhoenix.Form](https://hexdocs.pm/ash_phoenix/AshPhoenix.Form.html)

## Steps

1.  We can simplify a lot of our form code using `AshPhoenix.Form`.
    We get error handling, automatic setting of values, and more.

2.  To start, we will add this `assign_form/1` helper to the bottom of `lib/twitter_web/live/tweet_live/form.ex`.

```elixir
defp assign_form(%{assigns: %{tweet: tweet}} = socket) do
  form =
    if tweet do
      AshPhoenix.Form.for_update(tweet, :update,
        as: "tweet",
        actor: socket.assigns.current_user
      )
    else
      AshPhoenix.Form.for_create(Twitter.Tweets.Tweet, :create,
        as: "tweet",
        actor: socket.assigns.current_user
      )
    end

  assign(socket, form: to_form(form))
end
```

3. Then we can call it at the end of each `apply_action/3` clause. Replace your `apply_action/3` functions with the following code:

```elixir
defp apply_action(socket, :edit, %{"id" => id}) do
  socket
  |> assign(:page_title, "Edit Tweet")
  |> assign(
    :tweet,
    Twitter.Tweets.get_tweet!(id, actor: socket.assigns.current_user)
  )
  |> assign_form()
end

defp apply_action(socket, :new, _params) do
  socket
  |> assign(:page_title, "New Tweet")
  |> assign(:tweet, nil)
  |> assign_form()
end
```

4. Now, update your `"save"` handler to use `AshPhoenix.Form.submit/2`

To do this, we'll change our `"save"` event handler to the following. Notice how this `AshPhoenix.Form.submit/2` works regardless of the action type.

```elixir
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
```

5. Then, we can modify our `<.form>` to use this form.

```elixir
<.form for={@form} id="tweet-form" phx-submit="save" phx-change="validate">
  <.input label="Text" type="textarea" field={@form[:text]} />
  <footer>
    <.button phx-disable-with="Saving..." variant="primary">Save Tweet</.button>
    <.button navigate={~p"/"}>Cancel</.button>
  </footer>
</.form>
```

Notice how we've added `phx-change="validate"`

6. We can now add a `handle_event` function for the `"validate"` event.
   This adds validations on keystroke, and `AshPhoenix.Form` handles the complexity of that.

```elixir
@impl true
def handle_event("validate", %{"tweet" => tweet_params}, socket) do
  {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, tweet_params))}
end
```

7. Now we can try it out our tweet form, and if you violate any validations on the tweet,
   you will see the validation errors automatically appear as soon as you meet the error conditions.
   Try writing more than the character limit.
