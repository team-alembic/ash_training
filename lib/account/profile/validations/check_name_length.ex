defmodule Account.Profile.Validations.CheckNameLength do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _, _) do
    name = Ash.Changeset.get_attribute(changeset, :name)
    length = String.length(name)

    if length >= 2 and length <= 255 do
      :ok
    else
      {:error, field: :name, message: "must be at least 2 characters and less than 255"}
    end
  end
end
