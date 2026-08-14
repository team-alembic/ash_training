# Lab 4 - Calculations

## Relevant Documentation

- [Calculations](https://hexdocs.pm/ash/calculations.html)
- [Expressions](https://hexdocs.pm/ash/expressions.html)

## Steps

We want to display two things about a tweet in the UI.

- How many characters it has
- Whether or not the current user has liked it.

We will get into "how many likes does it have" in the next section on aggregates.

1. Let's add a calculation to the tweet resource to calculate the length of the text.

```elixir
calculate :text_length, :integer, expr(string_length(text))
```

You can also let Ash infer the type of an expression calculation with `:auto`:

```elixir
calculate :text_length, :auto, expr(string_length(text))
```

Ash works out that this returns an `:integer` from the expression itself. `:auto` only works for expression calculations — module calculations still need an explicit type.

2. Now, update `@tweet_loads` in `index.ex` like so (we'll extend this again in step 5):

```elixir
@tweet_loads [:text_length, user: [:email]]
```

3. And add a column to our table to show the length, right after the Text column

```heex
<:col :let={{_id, tweet}} label="Length">
  {tweet.text_length}
</:col>
```

4. Now we want to show if the current user has liked the tweet.

```elixir
calculate :liked_by_me, :boolean, expr(exists(likes, user_id == ^actor(:id)))
```

5. Now, lets replace our like and unlike buttons with a heart icon.
   Add `:liked_by_me` to `@tweet_loads`.

```elixir
@tweet_loads [:text_length, :liked_by_me, user: [:email]]
```

We will use this calculation to conditionally make the heart icon red.

Replace the like and unlike button actions with the following:

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
</:action>
```

Now you can like and unlike in one click!

6. Calculations aren't just for display — you can filter and sort on them too. Try this in `iex`:

```elixir
require Ash.Query

Twitter.Tweets.Tweet
|> Ash.Query.filter(text_length > 100)
|> Ash.Query.sort(text_length: :desc)
|> Ash.read!()
```

(`Ash.Query.filter/2` is a macro, so the `require Ash.Query` is needed first — without it you get a confusing "function is undefined or private" error.)

If you get back an empty list, none of your tweets are over 100 characters yet — create one and try again:

```elixir
user = Twitter.Accounts.User |> Ash.read!() |> List.first()
Ash.create!(Twitter.Tweets.Tweet, %{text: String.duplicate("ash! ", 30)}, action: :create, actor: user)
```

Ash pushes the calculation down into the query, so the database does the work. Keep this in mind for the next section — aggregates are filterable and sortable in the same way.

## Try on your own

- Use a module calculation to calculate the text length
- Use a module calculation to calculate the ratio of likes per character of text
- Use an expression calculation to calculate likes per character
- Note: the `load` option/callback belongs to module calculations only — expression calculations derive their dependencies from the expression itself, and Ash will warn at compile time if you set `load` on an expression calculation
- Stretch: give your likes-per-character calculation a `:precision` argument (declare `argument :precision, :integer` inside a `calculate ... do ... end` block) and sort by it: `Ash.Query.sort(likes_per_char: {%{precision: 2}, :desc})` — the map supplies values for the calculation's declared arguments
