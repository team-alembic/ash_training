defmodule Account.Profile.Preparations.SortByMostRecentlyCreated do
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _, _) do
    Ash.Query.build(query, sort: [created_at: :desc])
  end
end
