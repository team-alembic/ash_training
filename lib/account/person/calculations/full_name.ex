defmodule Account.Person.Calculations.FullName do
  use Ash.Resource.Calculation

  @impl true
  def load(_, _, _), do: [:first_name, :last_name]

  @impl true
  def calculate(records, _, _) do
    Enum.map(records, fn record ->
      record.first_name <> " " <> record.last_name
    end)
  end
end
