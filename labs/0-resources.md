# Lab 0 - Resources

## Relevant Documentation

- [Getting Started](https://hexdocs.pm/ash/get-started.html)
- [Attributes](https://hexdocs.pm/ash/attributes.html)
- [Domains](https://hexdocs.pm/ash/domains.html)
- [Ash.Resource.Info](https://hexdocs.pm/ash/Ash.Resource.Info.html)
- [Ash.Domain.Info](https://hexdocs.pm/ash/Ash.Domain.Info.html)
- [Ash.Info](https://hexdocs.pm/ash/Ash.Info.html)
- [AshPostgres.DataLayer.Info](https://hexdocs.pm/ash_postgres/AshPostgres.DataLayer.Info.html)

## Context

We have already created a domain module for you, called `Twitter.Tweets` in `lib/twitter/tweets.ex`.

## Steps

1. Run the following to generate a resource:

```bash
mix ash.gen.resource Twitter.Tweets.Tweet \
  --uuid-primary-key id \
  --default-actions read,destroy \
  --timestamps
```

This command

- adds a uuid primary key attribute to our resource
- adds a default read & destroy action
- adds the resource to the domain module `Twitter.Tweets`

The generator shows you the proposed changes and asks `Proceed with changes?` — answer `y` to apply them. (You can also pass `--yes` to skip the prompt. This applies to the `mix ash.gen.*` and `mix ash.extend` generators used in these labs — not to `mix ash.codegen`, which never prompts and doesn't accept `--yes`.)

2. Run `iex -S mix`, and use functions from `Ash.Resource.Info` to see that we've defined the resource properly. (ignore the warnings presented in iex)

```elixir
iex> Ash.Resource.Info.attributes(Twitter.Tweets.Tweet)
# [%Ash.Resource.Attribute{}]
```

```elixir
iex> Ash.Resource.Info.actions(Twitter.Tweets.Tweet)
# [%Ash.Resource.Actions.Destroy{}, %Ash.Resource.Actions.Read{}]
```

3. Open the domain module (`Twitter.Tweets`) and confirm that the generator added `Twitter.Tweets.Tweet` to its resource list. Ignore the extra content in the domain module for now.

   Note: domains themselves are listed under `ash_domains` in `config/config.exs` so Ash tooling can find them. You can run `mix ash.set.domains` to scan the app and update that list automatically instead of editing it by hand.

4. Use functions from `Ash.Domain.Info`

```elixir
iex> Ash.Domain.Info.resources(Twitter.Tweets)
# [...]
```

For a bird's-eye view of the whole app, `Ash.Info.manifest(otp_app: :twitter)` returns `{:ok, manifest}`, where the manifest describes every domain, resource, and action in one struct.

5. Run the following to add the `AshPostgres` extension to the resource:

```bash
mix ash.extend Twitter.Tweets.Tweet postgres
```

This command

- adds `data_layer: AshPostgres.DataLayer` to the `use Ash.Resource` statement
- configures a `repo` (`Twitter.Repo`)
- configures a `table`, inferred from the resource name, in this case `"tweets"`

```elixir
iex> AshPostgres.DataLayer.Info.table(Twitter.Tweets.Tweet)
# "tweets"
```

```elixir
iex> AshPostgres.DataLayer.Info.repo(Twitter.Tweets.Tweet)
# Twitter.Repo
```

## Try on your own

- Add a `:text` attribute to the `Tweet` resource, and check the `attributes` list with `Ash.Resource.Info` again.

- Change the table name to something else, and check the table name with `AshPostgres.DataLayer.Info` again. When you're done, change it back to `"tweets"` — later labs depend on that table name.
