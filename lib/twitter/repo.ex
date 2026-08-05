defmodule Twitter.Repo do
  use AshPostgres.Repo, otp_app: :twitter

  def installed_extensions do
    ["citext", "ash-functions", "vector"]
  end

  def min_pg_version do
    # ash_postgres needs PostgreSQL 17+ for MERGE ... RETURNING in bulk updates
    %Version{major: 17, minor: 0, patch: 0}
  end
end
