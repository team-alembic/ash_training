# Lab 2 - Relationships

## Relevant Documentation

- [Relationships](https://hexdocs.pm/ash/relationships.html)

## Steps

1. We want to associate tweets to a user, so we'll add a `belongs_to :user` relationship to the `Tweet` resource:

```elixir
relationships do
  belongs_to :user, Twitter.Accounts.User do
    allow_nil? false
  end
end
```

2. Don't forget the tasks you need to run to update the database! You will need to remove any existing tweets if you have created any.
   The easiest way is to do a reset with `mix ash.reset`.

3. Then we can add `:user_id` to the `accept` list for the `:create` action.

4. Next we'll add the following code to `create` block of our `"save"` handler in `lib/twitter_web/live/tweet_live/form.ex` (above the `Changeset.for_create` code). This will set the `:user_id` attribute to the current user's id when creating a tweet, by modifying the params.

We'll use `Map.put` to put the user_id in the tweet's params (for now).

```elixir
result =
  if socket.assigns.tweet do
    socket.assigns.tweet
    |> Ash.Changeset.for_update(:update, params["tweet"] || %{}, actor: socket.assigns.current_user)
    |> Ash.update()
  else
    # ** add the following line **
    params = put_in(params, ["tweet", "user_id"], socket.assigns.current_user.id)

    Twitter.Tweets.Tweet
    |> Ash.Changeset.for_create(:create, params["tweet"] || %{}, actor: socket.assigns.current_user)
    |> Ash.create()
  end
```

5. Now we can show the `email` of the user who created the tweet in the tweet list.
   At the top of the module in `index.ex`, add a module attribute called `@tweet_loads` containing the path to the data we want to load.

```elixir
@tweet_loads [user: [:email]]
```

6. Then, alter the call to `Ash.read!` in the `mount/3` function of `index.ex` to include the `load` option. `load: @tweet_loads`.
   For example: `Ash.read!(query, load: @tweet_loads)`.

7. When a tweet is saved, the form navigates back to the tweet list. The list is re-read
   in `mount/3`, so the freshly loaded data (including our new `load`) is picked up automatically —
   nothing else to do here.

8. Now we can show the email in a table column:

```elixir
<:col :let={{_id, tweet}} label="Author">
  <%= tweet.user.email %>
</:col>
```

9. Go try it out! Now, creating a tweet shows the email of the creator.
   If you ran `mix ash.reset`, you may need to sign up again.

10. To track when a tweet has been liked, we'll add a `Twitter.Tweets.Like` resource.

```bash
mix ash.gen.resource Twitter.Tweets.Like \
  --uuid-primary-key id \
  --default-actions read \
  --relationship belongs_to:tweet:Twitter.Tweets.Tweet:required \
  --relationship belongs_to:user:Twitter.Accounts.User:required \
  --extend postgres \
  --timestamps
```

11. Then we'll add a relationship on the `Tweet` resource, using `has_many`, showing that a tweet, `has_many` likes.

We'll use this relationship in upcoming labs!

12. Don't forget to run our tasks to update the database!

## Try on your own

- add a (temporary) `:create` action to `Like` to allow us to play with the relationships.

```elixir
create :create do
  accept [:tweet_id, :user_id]
end
```

- Create a like for a tweet in `iex -S mix`, like so:

```elixir
iex> tweet_id = Ash.first!(Twitter.Tweets.Tweet, :id)
iex> user_id = Ash.first!(Twitter.Accounts.User, :id)
iex> Twitter.Tweets.Like
     |> Ash.Changeset.for_create(:create, %{tweet_id: tweet_id, user_id: user_id})
     |> Ash.create!()
```

- Then try loading related likes for a tweet!

```elixir
iex> Twitter.Tweets.Tweet
     |> Ash.Query.load(:likes)
     |> Ash.read!()
```

- Generate resource diagrams with `mix ash.generate_resource_diagrams`. You can add the `--format png` option, but that requires `npm install -g @mermaid-js/mermaid-cli`, which people tend to have issues with due to node versions. To view the charts otherwise, paste the mermaid code into the [Mermaid Live Editor](https://mermaid.live/edit).

- Show the `user.id` in the tweet list in the same way we're showing the `user.email`.

- In `iex`, list all of the users, and load their tweets.

- Add a `dislikes` relationship, and a resource for tracking `dislikes`.
