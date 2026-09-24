defmodule Account.Profile.Changes.Publish do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.force_change_attribute(changeset, :status, :published)
  end
end
