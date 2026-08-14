# Lab 8 - `AshPhoenix.Form`

## Relevant Documentation

- [AshPhoenix.Form](https://hexdocs.pm/ash_phoenix/AshPhoenix.Form.html)
- [Code Interfaces](https://hexdocs.pm/ash/code-interfaces.html)

## Steps

1.  We can simplify a lot of our form code using `AshPhoenix.Form`.
    We get error handling, automatic setting of values, and more.
    We'll be working in the tweet form LiveView, `TwitterWeb.TweetLive.Form`,
    which lives in `lib/twitter_web/live/tweet_live/form.ex`.

2.  The recommended way to build forms is through your domain's code interface.
    Any `define` in the domain gets a matching `form_to_*` function when the
    domain uses the `AshPhoenix` extension. First, add `AshPhoenix` to the
    `extensions` list at the top of `lib/twitter/tweets.ex`:

```elixir
use Ash.Domain,
  extensions: [AshJsonApi.Domain, AshAdmin.Domain, AshPhoenix]
```

Then add these two definitions to the `Twitter.Tweets.Tweet` block:

```elixir
define :create_tweet, action: :create
define :update_tweet, action: :update
```

This gives us `Twitter.Tweets.form_to_create_tweet/1` and
`Twitter.Tweets.form_to_update_tweet/2` for free. As covered in the code
interface lab, each `define` also generates the plain
`Twitter.Tweets.create_tweet/1` and `Twitter.Tweets.update_tweet/2` functions.

3.  Now we can add this `assign_form/1` helper to the bottom of the LiveView.

```elixir
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
```

Under the hood these functions call `AshPhoenix.Form.for_update/3` and
`AshPhoenix.Form.for_create/3` — you can always drop down to that API directly,
but the code interface keeps your web layer talking to your domain, not to
individual resources.

4.  This LiveView sets up its assigns in `apply_action/3`, which runs from
    `mount/3` for both the `:new` and `:edit` live actions. Call `assign_form/1`
    at the end of each clause, after `:tweet` has been assigned:

Keep the `Ash.can?` authorization check from Lab 6 — we're only adding
`assign_form()` to both branches:

```elixir
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
```

5.  Now, update your `"save"` handler to use `AshPhoenix.Form.submit/2`.
    Notice how `AshPhoenix.Form.submit/2` works regardless of the action type —
    the form already knows whether it's creating or updating.

```elixir
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
```

On success we navigate away; on failure we re-assign the form, which now
carries the errors for the template to display.

`form.source.type` works because `assign_form/1` wrapped the form in
`to_form/1`: `@form` is a `Phoenix.HTML.Form` whose `source` is the underlying
`AshPhoenix.Form`, and its `type` is `:create` or `:update`.

6.  Then, we can point the `<.form>` in `render/1` at our form.

```elixir
<.form for={@form} id="tweet-form" phx-submit="save" phx-change="validate">
  <.input label="Text" type="textarea" field={@form[:text]} />
  <footer>
    <.button phx-disable-with="Saving..." variant="primary">Save Tweet</.button>
    <.button navigate={~p"/"}>Cancel</.button>
  </footer>
</.form>
```

Notice the `phx-change="validate"` binding.

7.  We can now add a `handle_event` function for the `"validate"` event.
    This adds validations on keystroke, and `AshPhoenix.Form` handles the complexity of that.

```elixir
def handle_event("validate", %{"tweet" => tweet_params}, socket) do
  {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, tweet_params))}
end
```

8.  Now we can try out our tweet form, and if you violate any validations on the tweet,
    you will see the validation errors automatically appear as soon as you meet the error conditions.
    Try writing more than the character limit.
