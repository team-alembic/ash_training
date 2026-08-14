# Lab 5 - Aggregates

## Relevant Documentation

- [Aggregates](https://hexdocs.pm/ash/aggregates.html)

## Steps

1. We want to see how many likes a tweet has. We can do this by adding an
   aggregate to the tweet resource. `Twitter.Tweets.Tweet` doesn't have an
   `aggregates` section yet, so add one (right after the `calculations` block
   is a good spot):

```elixir
aggregates do
  count :like_count, :likes
end
```

The rest of the aggregates in this lab go inside this same block.

2. Now we can add `:like_count` to our `@tweet_loads` in `index.ex`, and then display it next to the heart icon.

```elixir
@tweet_loads [:text_length, :liked_by_me, :like_count, user: [:email]]
```

```elixir
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

  <%!-- Add the line below --%>
  {tweet.like_count}
</:action>
```

3. So far in our application, for showing the user's email, we have been loading the user for
   each tweet (we have `user: [:email]` in `@tweet_loads`).

We can use the `first` aggregate for this. Not only is this more efficient, but it will also
make the next section on policies simpler.

```elixir
first :user_email, :user, :email
```

4. Then, replace `user: [:email]` from `@tweet_loads` with `:user_email`, and change `{tweet.user.email}` to `{tweet.user_email}` in the Author column (the old code would crash now that `user` is no longer loaded):

```elixir
@tweet_loads [:text_length, :liked_by_me, :like_count, :user_email]
```

```elixir
<:col :let={{_id, tweet}} label="Author">
  {tweet.user_email}
</:col>
```

Now, we only make a single query when fetching the tweet, instead of two! (One for the tweet, and one for the user.) You can see the modified sql query in the logs.

5. Aggregates can also be filtered. Let's count only the likes a tweet received in the last day, by adding a `filter` inside the aggregate:

```elixir
count :like_count_today, :likes do
  filter expr(inserted_at >= ago(1, :day))
end
```

Optionally, try adding `:like_count_today` to `@tweet_loads` and displaying it — the filter is applied inside the aggregate, so everything still happens in that single query. (This is just to see it working; the later labs don't use it.)

6. Finally, there is an `exists` aggregate: a cheaper way of asking "are there any?" than counting and comparing to zero.

```elixir
exists :has_likes, :likes
```

You've already seen `exists(...)` used inside an expression, in our `liked_by_me` calculation — this is the aggregate flavour of the same idea.

We won't wire `has_likes` into the UI — you can verify it works in `iex -S mix` with `Twitter.Tweets.Tweet |> Ash.read!() |> Ash.load!(:has_likes)`.

## Try on your own

- Add a `first` aggregate to get the "email of the user who most recently liked the tweet".
  Hint: an aggregate's `sort` sorts the destination resource, so go through `:likes` (which
  has timestamps) rather than through the users. `Like` has no email field, though — add
  `calculate :liker_email, :ci_string, expr(user.email)` to `Like` and use that calculation
  as the aggregate's field.
- Add a `list` aggregate to get the "emails of all users who liked the tweet"
- Add a `max` aggregate to users to get the "amount of likes on their most liked tweet"
  (you'll need to add a `has_many :tweets` relationship to `User` first)

Note for the last one: aggregates can reference other aggregates on the related resource. So `like_count` — itself an aggregate on `Tweet` — can be used directly as the field of an aggregate on `User`. Very little in your database is out of reach once you start stacking aggregates like this!
