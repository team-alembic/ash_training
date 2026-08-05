# Twitter

## Lab branches

Each lab has a branch that contains the **starting point** for that lab — which
also means it contains the solutions for all previous labs:

- `lab-00-resources` … `lab-14-ash-ai-reactor` — starting points for labs 0–14
  (see `labs/`)
- `final-solution` — everything solved, including lab 14

To start (or catch up at) lab N, check out its branch, e.g.:

```bash
git checkout lab-06-policies
mix setup
```

The branches form one linear history: each lab's solution is a single commit on
top of the previous branch.

### Maintaining the branches

To fix something in an earlier lab, edit that lab's solution commit with an
interactive rebase and let `--update-refs` carry all later lab branches along:

```bash
git rebase -i --update-refs lab-00-resources~1 final-solution
```

If a fix changes a resource's database shape, regenerate the migrations of the
affected lab commit (and any later ones) with `mix ash.codegen` as you go.

## Setup

To get started, you will want to ensure that you have

- a terminal (Terminal.app, iTerm2)
- a recent version of Elixir
- a recent version of Erlang
- a recent version of Postgresql
- a code editor

These instructions are for mac & linux. If you are on windows, we will figure it out in person. It is absolutely not a problem if you are.

### Terminal

You can use the builtin terminal. Otherwise,I recommend iTerm2.

### Create database

`mix setup`

If you don't have elixir/erlang/postgresql installed, see below.

### Installing Erlang/Elixir/Postgresql

If you already have these installed, you can skip the rest of this document.

#### Installing `homebrew`

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### Installing `asdf`

If you already have `asdf` installed, you can skip this section. If you don't know your shell, use `echo $SHELL` in your terminal. If you use a different shell, we'll figure it out in person.

```bash
brew install asdf

# if your shell is bash
echo -e "\n. \"$(brew --prefix asdf)/libexec/asdf.sh\"" >> ~/.bashrc
echo -e "\n. \"$(brew --prefix asdf)/etc/bash_completion.d/asdf.bash\"" >> ~/.bashrc

# if your shell is zsh
echo -e "\n. \"$(brew --prefix asdf)/libexec/asdf.sh\"" >> ~/.zshrc
echo -e "\n. \"$(brew --prefix asdf)/etc/bash_completion.d/asdf.bash\"" >> ~/.zshrc
```

#### Installing Elixir/Erlang with asdf

```bash
# in the project root directory
asdf install
```

#### Installing Postgresql

```bash
brew install postgresql@16
brew services start postgresql@16
createuser -s postgres
```
