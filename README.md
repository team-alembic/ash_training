# Twitter

## Lab branches

Each lab has a branch that contains the **starting point** for that lab — which
also means it contains the solutions for all previous labs:

- `lab-00-resources` … `lab-16-spark-extensions` — starting points for labs 0–16
  (see `labs/`)
- `main` — everything solved, including lab 16

To start (or catch up at) lab N, check out its branch, e.g.:

```bash
git checkout lab-06-policies
mix setup
```

The branches form one linear history: each lab's solution is a single commit on
top of the previous branch.

> **Switching branches around labs 12–15?** `ash_ai` bakes in support for the
> optional `req_llm` dependency when it is compiled, so a branch switch can
> leave a stale build and the compiler will claim `req_llm` is missing even
> though it is right there in `mix.exs`. Rebuild it:
>
> ```bash
> mix deps.compile ash_ai --force
> ```

## Setup

You need a terminal, a code editor, Erlang, Elixir and PostgreSQL.

These instructions are for mac & linux. If you are on windows, we will figure it
out in person. It is absolutely not a problem if you are.

### Erlang & Elixir

The exact versions are pinned in `.tool-versions`. Use [mise] to install them —
it reads that file and gets everyone onto identical versions:

```bash
# install mise (see https://mise.jdx.dev/installing-mise.html for other options)
curl https://mise.run | sh

# in the project root directory
mise install
```

Add mise to your shell so the pinned versions are picked up automatically
(`echo $SHELL` if you're not sure which you use):

```bash
# bash
echo 'eval "$(mise activate bash)"' >> ~/.bashrc

# zsh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc

# fish
echo 'mise activate fish | source' >> ~/.config/fish/config.fish
```

Open a new terminal, then check you got the right versions:

```bash
elixir --version
```

<details>
<summary>Already using asdf instead?</summary>

`.tool-versions` works with asdf too — no need to switch:

```bash
asdf install
```

</details>

[mise]: https://mise.jdx.dev

### PostgreSQL

From lab 13 on, the database needs the `pgvector` extension, so a plain
PostgreSQL install is not enough. The easiest route is Docker:

```bash
mise run db-up     # Postgres 18 + pgvector on :5432, user/password postgres
mise run db-down   # when you're done
```

<details>
<summary>Prefer a local install?</summary>

```bash
brew install postgresql@18 pgvector
brew services start postgresql@18
createuser -s postgres
```

</details>

### Create the database

```bash
mise run setup     # or: mix setup
```

### Running things

```bash
mise run server    # Phoenix on http://localhost:4000
mise run test      # test suite
mise tasks         # everything available
```
