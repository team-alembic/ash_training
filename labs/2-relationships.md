# Lab 2 - Relationships

## Relevant Documentation

- [Relationships](https://hexdocs.pm/ash/relationships.html)

## Steps

1. We want to associate tweets to a user, so we'll add a `belongs_to :user`
   relationship to the `Tweet` resource:

```elixir
relationships do
  belongs_to :user, Twitter.Accounts.User do
    allow_nil? false
  end
end
```

2. Now update the database. Generate the migration, then reset:

```bash
mix ash.codegen add_user_to_tweet
mix ash.reset
```

> `mix ash.codegen` prints a warning about "destructive operations" — don't
> panic. The `up` migration only _adds_ a column; the warning is triggered by
> the auto-generated rollback (`down`) code, which drops the foreign key again.

Normally `mix ash.migrate` is all you need to apply a new migration, but the new
`user_id` column is `NOT NULL`, so the migration fails if you already created
any tweets. `mix ash.reset` drops and recreates the database, which is the
easiest way around that here.

3. Then we can add `:user_id` to the `accept` list for the `:create` action.

> **Note:** the test suite that ships with the repo
> (`test/twitter/tweets/tweet_test.exs`) still creates a tweet with only
> `:text`, so `mix test` fails from this point on. Fix it by seeding a user and
> passing its id — add a `setup` block and use the user in the CRUD test:
>
> ```elixir
> setup do
>   user =
>     Ash.Seed.seed!(Twitter.Accounts.User, %{
>       email: "user-#{System.unique_integer([:positive])}@example.com",
>       hashed_password: "not-used-in-tests"
>     })
>
>   %{user: user}
> end
>
> test "creates, updates, and destroys a tweet", %{user: user} do
>   tweet = Ash.create!(Tweet, %{text: "first", user_id: user.id}, action: :create)
>   # ... rest of the test stays the same
> end
> ```

4. Next we'll add the following code to `create` block of our `"save"` handler
   in `lib/twitter_web/live/tweet_live/form.ex` (above the
   `Changeset.for_create` code). This will set the `:user_id` attribute to the
   current user's id when creating a tweet, by modifying the params.

We'll use `put_in` to put the user_id in the tweet's params (for now). Don't
worry, we'll replace this hack with a much nicer approach (`relate_actor`) in
Lab 3!

```elixir
result =
  if socket.assigns.tweet do
    socket.assigns.tweet
    |> Ash.Changeset.for_update(:update, params["tweet"] || %{},
      actor: socket.assigns.current_user
    )
    |> Ash.update()
  else
    # ** add the following line **
    params = put_in(params, ["tweet", "user_id"], socket.assigns.current_user.id)

    Twitter.Tweets.Tweet
    |> Ash.Changeset.for_create(:create, params["tweet"] || %{},
      actor: socket.assigns.current_user
    )
    |> Ash.create()
  end
```

5. Now we can show the `email` of the user who created the tweet in the tweet
   list. At the top of the module in `index.ex`, add a module attribute called
   `@tweet_loads` containing the path to the data we want to load.

```elixir
@tweet_loads [user: [:email]]
```

6. Then, alter the call to `Ash.read!` in the `mount/3` function of `index.ex`
   to include the `load` option, `load: @tweet_loads`:

```elixir
Ash.read!(Twitter.Tweets.Tweet,
  actor: socket.assigns.current_user,
  action: :read,
  load: @tweet_loads
)
```

7. When a tweet is saved, the form navigates back to the tweet list. The list is
   re-read in `mount/3`, so the freshly loaded data (including our new `load`)
   is picked up automatically — nothing else to do here.

8. Now we can show the email in a table column:

```elixir
<:col :let={{_id, tweet}} label="Author">
  <%= tweet.user.email %>
</:col>
```

9. Go try it out! Since `mix ash.reset` wiped the database in step 2, sign up
   again first. Now, creating a tweet shows the email of the creator.

10. To track when a tweet has been liked, we'll add a `Twitter.Tweets.Like`
    resource.

```bash
mix ash.gen.resource Twitter.Tweets.Like \
  --uuid-primary-key id \
  --default-actions read \
  --relationship belongs_to:tweet:Twitter.Tweets.Tweet:required \
  --relationship belongs_to:user:Twitter.Accounts.User:required \
  --extend postgres \
  --timestamps
```

11. Then we'll add a relationship on the `Tweet` resource, using `has_many`,
    showing that a tweet `has_many` likes. Add this to the `relationships` block
    of `Twitter.Tweets.Tweet`:

```elixir
has_many :likes, Twitter.Tweets.Like
```

We'll use this relationship in upcoming labs!

12. Relationships can also traverse _other_ relationships. A tweet
    `has_many :likes`, and each like `belongs_to :user` — so we can define a
    relationship that goes straight from a tweet to the users who liked it,
    using `through`:

```elixir
has_many :likers, Twitter.Accounts.User do
  through [:likes, :user]
end
```

Note that `through` takes a _path of relationship names_, and Ash follows it to
the destination resource. No join resource or extra columns needed — it reuses
the relationships we already have.

13. Don't forget to update the database! This time the migration creates a
    brand-new (empty) table, so a plain migrate is enough — no reset needed:

```bash
mix ash.codegen add_likes
mix ash.migrate
```

## Try on your own

- add a (temporary) `:create` action to `Like` to allow us to play with the
  relationships.

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

- Load the `:likers` relationship the same way. Notice you get `User` structs
  back directly, even though we never defined a join between tweets and users —
  the `through` path did the work.

- `has_many` relationships also accept `sort` and `limit` options. Try adding a
  `recent_likes` relationship to `Tweet` that only loads the 3 most recent
  likes, and load it in `iex`:

```elixir
has_many :recent_likes, Twitter.Tweets.Like do
  sort inserted_at: :desc
  limit 3
end
```

- Generate resource diagrams with `mix ash.generate_resource_diagrams`. You can
  add the `--format png` option, but that requires
  `npm install -g @mermaid-js/mermaid-cli`, which people tend to have issues
  with due to node versions. To view the charts otherwise, paste the mermaid
  code into the [Mermaid Live Editor](https://mermaid.live/edit).

- Show the `user.id` in the tweet list in the same way we're showing the
  `user.email`.

- In `iex`, list all of the users, and load their tweets. (Hint: loading
  `:tweets` on a user only works after you define the relationship — add a
  `has_many :tweets, Twitter.Tweets.Tweet` to the `Twitter.Accounts.User`
  resource first. No migration needed; the foreign key already lives on the
  tweets table.)

- Add a `dislikes` relationship, and a resource for tracking `dislikes`.
