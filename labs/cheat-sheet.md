# Cheat Sheet

## Run IEx

```elixir
iex -S mix
```

## Run IEx with the phoenix server

This gives you a running phoenix server and an IEx prompt.

```elixir
iex -S mix phx.server
```

## Run just the phoenix server

```elixir
mix phx.server
```

## Generate Migrations

```
mix ash.codegen <what_changed_here>
```

While iterating, you can skip naming your changes:

```
mix ash.codegen --dev
```

When you're happy, run `mix ash.codegen <what_changed_here>` to squash the dev
migrations into a properly named one.

## Run Migrations

```
mix ash.migrate
```

## Reset the database

```
mix ash.reset
```

## Code Interface

Defined in the domain, inside the block for a resource:

```elixir
resource Twitter.Tweets.Tweet do
  define :feed
  define :get_tweet, action: :read, get_by: [:id]
  define :like, args: [:tweet_id]
end
```

Each `define` generates a `{:ok, _}`/`{:error, _}` returning function
(`Twitter.Tweets.feed()`), a raising `!` variant (`Twitter.Tweets.feed!()`), and
`can_*`/`can_*?` helpers that check your policies without running the action.
Names ending in `?` instead generate a single predicate function that returns a
plain boolean.

### Forms via the Code Interface (`AshPhoenix`)

Add the `AshPhoenix` extension to the domain to also get a `form_to_*` function
for each `define`:

```elixir
use Ash.Domain,
  extensions: [AshPhoenix]
```

```elixir
# define :create_tweet, action: :create   ->
form = Twitter.Tweets.form_to_create_tweet(actor: user)

# define :update_tweet, action: :update   ->
form = Twitter.Tweets.form_to_update_tweet(tweet, actor: user)
```

These return an `AshPhoenix.Form` (built via `AshPhoenix.Form.for_action/3`),
ready for `to_form/1`, `AshPhoenix.Form.validate/2`, and
`AshPhoenix.Form.submit/2`.

## AshJsonApi

Only fields marked `public? true` (attributes, calculations, aggregates) are
exposed. Resource-level config lives in the `json_api` block:

```elixir
json_api do
  type "tweet"

  # Serialize (and accept in filters/sorts/fieldsets) fields as camelCase
  field_names :camelize

  # Hide an already-public field from this JSON:API interface only
  hide_fields [:updated_at]

  routes do
    base "/tweets"

    index :feed                # GET /tweets
    get :read, primary?: true  # GET /tweets/:id (primary? -> used for self links)
    post :create               # POST /tweets
    patch :update              # PATCH /tweets/:id
    delete :destroy            # DELETE /tweets/:id
  end
end
```

## IEx Cheat Sheet

### Recompile after changes

If you are running the browser application, you can refresh the browser.
Otherwise:

```elixir
recompile
```
