# :external tests hit live AI APIs; include them with: mix test --include external
ExUnit.start(exclude: [:external])
Ecto.Adapters.SQL.Sandbox.mode(Twitter.Repo, :manual)
