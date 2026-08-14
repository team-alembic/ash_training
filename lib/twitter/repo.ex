defmodule Twitter.Repo do
  use AshPostgres.Repo, otp_app: :twitter

  def installed_extensions do
    ["citext", "ash-functions"]
  end

  def min_pg_version do
    # PG 17+ enables MERGE-based upserts in ash_postgres >= 2.10
    %Version{major: 17, minor: 0, patch: 0}
  end
end
