# Lab 16 - Building your own extension: soft deletes

## Relevant Documentation

- [Spark: Writing Extensions](https://hexdocs.pm/spark/writing-extensions.html)
- [Spark.Dsl.Section](https://hexdocs.pm/spark/Spark.Dsl.Section.html)
- [Spark.Dsl.Transformer](https://hexdocs.pm/spark/Spark.Dsl.Transformer.html)
- [Spark.InfoGenerator](https://hexdocs.pm/spark/Spark.InfoGenerator.html)
- [Ash.Resource.Builder](https://hexdocs.pm/ash/Ash.Resource.Builder.html)
- [AshArchival](https://hexdocs.pm/ash_archival) — the real thing we are
  imitating

## Context

Every Ash feature you have used so far — `postgres do ... end`,
`json_api do ... end`, `vectorize do ... end` — is an **extension**: a bundle of
DSL sections plus code that runs at compile time and rewrites the resource based
on what you wrote. Nothing about them is special to Ash core; you can write one
in your own project with the same tools.

In this lab we build a bare-bones `AshArchival`. A resource that adds our
extension gets **soft deletes**:

- an `archived_at` attribute is added (`nil` means the record is live),
- every destroy action becomes an update that stamps `archived_at`, and
- every read action skips archived records.

We will apply it to `Twitter.Tweets.Tweet`: deleting a tweet then hides it
everywhere — feed, JSON:API, GraphQL, MCP tools — without deleting the row.

An extension has up to four parts, and we will write three of them:

| Part         | What it is                                                                                |
| ------------ | ----------------------------------------------------------------------------------------- |
| Extension    | `use Spark.Dsl.Extension` — declares DSL sections, transformers and verifiers             |
| Info         | `use Spark.InfoGenerator` — introspection functions for reading what the user configured  |
| Transformers | run at compile time and may **change** the resource (add attributes, rewrite actions)     |
| Verifiers    | run last and may only **check** the final resource and raise errors — _"try on your own"_ |

## Steps

### 1. Define the extension and its DSL

Create `lib/twitter/archival.ex`. The DSL is a single section with one option,
so the attribute name can be changed per resource:

```elixir
defmodule Twitter.Archival do
  @moduledoc "Soft-deletes for Ash resources: a bare-bones AshArchival."

  @archive %Spark.Dsl.Section{
    name: :archive,
    describe: "Configure how records of this resource are archived instead of destroyed.",
    examples: [
      """
      archive do
        attribute :deleted_at
      end
      """
    ],
    schema: [
      attribute: [
        type: :atom,
        default: :archived_at,
        doc: "The attribute that records when a record was archived. `nil` means it is live."
      ]
    ]
  }

  use Spark.Dsl.Extension, sections: [@archive]
end
```

The `schema` is a [`Spark.Options`](https://hexdocs.pm/spark/Spark.Options.html)
schema — the same kind used for `use Ash.Resource` options. Spark validates it
for you at compile time, generates docs from `describe`/`doc`, and feeds the
Elixir language server so you get autocomplete and hover help inside
`archive do ... end`.

Reading the configuration back out of a resource is the job of an **Info**
module. Create `lib/twitter/archival/info.ex`:

```elixir
defmodule Twitter.Archival.Info do
  @moduledoc "Introspection helpers for `Twitter.Archival`."
  use Spark.InfoGenerator, extension: Twitter.Archival, sections: [:archive]
end
```

That one line generates `archive_attribute/1` (returns `{:ok, value}` /
`:error`), `archive_attribute!/1` and `archive_options/1` — one pair per option
in the section, named `<section>_<option>`.

Now add the extension to the tweet resource in `lib/twitter/tweets/tweet.ex`:

```elixir
use Ash.Resource,
  ...
  extensions: [
    AshGraphql.Resource,
    AshJsonApi.Resource,
    AshAi,
    AshOban,
    Twitter.Archival
  ]
```

Recompile and check in `iex -S mix` that the default is picked up. Nothing else
happens yet — an extension with only sections is just configuration:

```elixir
Twitter.Archival.Info.archive_attribute!(Twitter.Tweets.Tweet)
# => :archived_at
```

### 2. A transformer that adds the attribute

Transformers receive the whole resource as a `dsl_state` and return a modified
one. Create `lib/twitter/archival/transformers/setup_archival.ex`:

```elixir
defmodule Twitter.Archival.Transformers.SetupArchival do
  @moduledoc false
  use Spark.Dsl.Transformer

  import Ash.Expr
  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    attribute = Twitter.Archival.Info.archive_attribute!(dsl_state)

    add_archive_attribute(dsl_state, attribute)
  end

  defp add_archive_attribute(dsl_state, attribute) do
    Ash.Resource.Builder.add_new_attribute(dsl_state, attribute, :utc_datetime_usec,
      public?: false,
      allow_nil?: true
    )
  end
end
```

Two things to notice:

- The Info module works on a `dsl_state` just as well as on a compiled resource
  module — that's what makes it usable inside transformers.
- `Ash.Resource.Builder` is Ash's toolbox for transformers. `add_new_attribute`
  builds a real `%Ash.Resource.Attribute{}` (validated against the attribute DSL
  schema, exactly as if you had typed it) and appends it — unless the resource
  already has one with that name.

Register the transformer in the extension:

```elixir
use Spark.Dsl.Extension,
  sections: [@archive],
  transformers: [Twitter.Archival.Transformers.SetupArchival]
```

Because the attribute is part of the compiled resource, AshPostgres sees it like
any other — generate and run the migration:

```sh
mix ash.codegen add_tweet_archival
mix ash.migrate
```

Have a look at the migration: an `archived_at :utc_datetime_usec` column on
`tweets`. In `iex`,
`Ash.Resource.Info.attribute(Twitter.Tweets.Tweet, :archived_at)` now returns
the attribute. It is `public? false`, so it stays out of JSON:API, GraphQL and
the MCP tools automatically.

### 3. Turn destroys into soft destroys

Ash destroy actions have a `soft?` flag: a soft destroy runs as an **update**
using the action's changes instead of deleting the row. So "make every destroy
an update that sets `archived_at`" is: for each destroy action, set
`soft?: true` and prepend a `set_attribute` change.

Add this to the transformer and call it from `transform/1`:

```elixir
def transform(dsl_state) do
  attribute = Twitter.Archival.Info.archive_attribute!(dsl_state)

  with {:ok, dsl_state} <- add_archive_attribute(dsl_state, attribute) do
    soften_destroy_actions(dsl_state, attribute)
  end
end

defp soften_destroy_actions(dsl_state, attribute) do
  dsl_state
  |> Transformer.get_entities([:actions])
  |> Enum.filter(&(&1.type == :destroy))
  |> Enum.reduce_while({:ok, dsl_state}, fn destroy, {:ok, dsl_state} ->
    set_archived_at =
      Ash.Resource.Change.Builtins.set_attribute(attribute, &DateTime.utc_now/0)

    case Ash.Resource.Builder.build_action_change(set_archived_at) do
      {:ok, change} ->
        archive = %{destroy | soft?: true, changes: [change | destroy.changes]}

        {:cont,
         {:ok,
          Transformer.replace_entity(
            dsl_state,
            [:actions],
            archive,
            &(&1.name == destroy.name)
          )}}

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end)
end
```

`Transformer.get_entities/2` returns the entities at a DSL path — here, every
action struct. `replace_entity/4` swaps one out, matched by the predicate.
Builders return `{:ok, _} | {:error, _}`, so a transformer that touches several
entities is usually a `reduce_while` over them.

Now recompile and check the default destroy action in `iex`:

```elixir
Ash.Resource.Info.action(Twitter.Tweets.Tweet, :destroy).soft?
# => true
```

That worked — but look closer at what we relied on. The tweet resource declares
its destroy with `defaults [:read, :destroy]`, and those defaults are only
turned into real action structs by one of Ash's own transformers,
`Ash.Resource.Transformers.SetPrimaryActions`. Had that one run after ours,
`get_entities` would never have seen a destroy action and nothing would have
been rewritten.

Spark runs transformers in **dependency order**: each transformer can say
`before?/1` or `after?/1` about others, and Spark topologically sorts them.
Between transformers with no declared relationship, the order falls back to the
order the extensions are listed in — Ash's own extension comes first, which is
the only reason it worked. That's an accident, not a contract, so declare the
dependency explicitly in the transformer:

```elixir
# `defaults [:read, :destroy]` only become real actions inside this
# transformer, so we have to run after it to see them.
def after?(Ash.Resource.Transformers.SetPrimaryActions), do: true
def after?(_), do: false
```

Now try it end to end in `iex`:

```elixir
user = Twitter.Accounts.User |> Ash.read!() |> List.first()
tweet = Twitter.Tweets.create_tweet!(%{text: "soon gone"}, actor: user)
Twitter.Tweets.delete_tweet!(tweet.id, actor: user)

Twitter.Repo.get!(Twitter.Tweets.Tweet, tweet.id).archived_at
# => ~U[2026-09-28 13:37:00.000000Z]
```

The row is still there — but so far it still shows up in the feed.

### 4. Hide archived records from every read

Finally, all read actions should only return live records. Ash has a place for
"runs for every read action": resource-wide **preparations**
(`preparations do prepare ... end`). Add one from the transformer:

```elixir
def transform(dsl_state) do
  attribute = Twitter.Archival.Info.archive_attribute!(dsl_state)

  with {:ok, dsl_state} <- add_archive_attribute(dsl_state, attribute),
       {:ok, dsl_state} <- filter_read_actions(dsl_state, attribute) do
    soften_destroy_actions(dsl_state, attribute)
  end
end

defp filter_read_actions(dsl_state, attribute) do
  Ash.Resource.Builder.add_preparation(
    dsl_state,
    Ash.Resource.Preparation.Builtins.build(filter: expr(is_nil(^ref(attribute))))
  )
end
```

`^ref(attribute)` builds a reference to whichever attribute the user configured
— the expression is `is_nil(archived_at)` on tweets and `is_nil(deleted_at)` on
a resource that renamed it.

> Why not loop over the read actions and set each one's `filter`, the way we
> looped over the destroys? Try it: Ash warns at compile time that the **primary
> read action has filters**. The primary read is also what Ash uses to load
> relationships and to check policies, so filtering it is flagged as a likely
> mistake. A resource-wide preparation runs in all the same places without the
> warning — and it is what AshArchival does too.

Recompile and check: the tweet you archived in step 3 is gone from
`Twitter.Tweets.feed!(actor: user)`, `Ash.get` no longer finds it, the JSON:API
`GET /api/json/tweets` and the `read_feed` MCP tool don't return it, and loading
it through a relationship (`Ash.load!(like, :tweet)`) gives `nil`. Start the
server and delete a tweet in the UI — same thing, except the row is still in the
database.

### 5. Fix and extend the tests

Run `mix test`. One test now fails:

```
test/twitter/tweets/tweet_test.exs: destroying a tweet cascades to its likes
```

Of course — the tweet is no longer deleted, so the `on_delete: :delete`
reference on `likes` never fires. Rewrite the test to describe the new
behaviour:

```elixir
test "destroying a tweet archives it and keeps its likes", %{user: user} do
  tweet = Ash.create!(Tweet, %{text: "temporary"}, action: :create, actor: user)
  Ash.create!(Like, %{tweet_id: tweet.id}, action: :like, actor: user)

  Ash.destroy!(tweet, actor: user)

  assert Ash.read!(Tweet) == []
  assert [%Like{tweet_id: tweet_id}] = Ash.read!(Like)
  assert tweet_id == tweet.id
end
```

Then add `test/twitter/archival_test.exs` for the extension itself. Good things
to assert:

- `Ash.Resource.Info.attribute(Tweet, :archived_at)` exists and is
  `public?: false`
- every destroy action of `Tweet` has `soft?: true` and a `SetAttribute` change
  for `:archived_at`
- a destroyed tweet is missing from `Ash.read!`, from the feed and from
  `Ash.get`, but `Twitter.Repo.get!(Tweet, id).archived_at` is set
- the `archive do attribute :deleted_at end` option works: define a throwaway
  resource **in the test file** with `data_layer: Ash.DataLayer.Ets` and the
  extension, and check `Twitter.Archival.Info.archive_attribute!/1` and that
  destroying a record hides it from `Ash.read!`. (A resource needs a domain —
  define a small `use Ash.Domain, validate_config_inclusion?: false` in the test
  file too.)

## Try on your own

- Add an `exclude_read_actions` option (`type: {:list, :atom}, default: []`) and
  use it to give tweets a `read :archived` action that shows only archived
  tweets — then check it out in AshAdmin. You'll need a
  [custom preparation module](https://hexdocs.pm/ash/Ash.Resource.Preparation.html)
  instead of `build/1`, so it can look at `query.action.name`.
- Archive related records: an `archive_related [:likes]` option that adds a
  change to the destroy actions which archives the related likes as well
  (`Ash.bulk_destroy/4` on the relationship). Have a look at how
  [AshArchival does it](https://github.com/ash-project/ash_archival/blob/main/lib/ash_archival/resource/changes/archive_related.ex).
- Add a **verifier** (`use Spark.Dsl.Verifier`, registered under `verifiers:`)
  that raises a `Spark.Error.DslError` when the configured attribute already
  exists on the resource with a type other than `:utc_datetime_usec`.
- Run `mix spark.cheat_sheets --extensions Twitter.Archival` and look at the
  generated DSL documentation. Then hover over `attribute` inside the `archive`
  block in your editor.
- Compare your ~80 lines with the real
  [`AshArchival.Resource.Transformers.SetupArchival`](https://github.com/ash-project/ash_archival/blob/main/lib/ash_archival/resource/transformers/setup_archival.ex)
  — it is the same shape.
