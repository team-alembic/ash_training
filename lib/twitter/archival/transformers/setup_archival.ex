defmodule Twitter.Archival.Transformers.SetupArchival do
  @moduledoc false
  # Rewrites the resource at compile time: adds the archive attribute, filters
  # archived records out of every read action and turns every destroy action
  # into a soft destroy (an update that stamps the archive attribute).
  use Spark.Dsl.Transformer

  import Ash.Expr
  alias Spark.Dsl.Transformer

  # `defaults [:read, :destroy]` only become real actions inside this
  # transformer, so we have to run after it to see them.
  def after?(Ash.Resource.Transformers.SetPrimaryActions), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    attribute = Twitter.Archival.Info.archive_attribute!(dsl_state)

    with {:ok, dsl_state} <- add_archive_attribute(dsl_state, attribute),
         {:ok, dsl_state} <- filter_read_actions(dsl_state, attribute) do
      soften_destroy_actions(dsl_state, attribute)
    end
  end

  defp add_archive_attribute(dsl_state, attribute) do
    Ash.Resource.Builder.add_new_attribute(dsl_state, attribute, :utc_datetime_usec,
      public?: false,
      allow_nil?: true
    )
  end

  # A resource-wide preparation runs for every read action, including the
  # primary one used when loading relationships. Putting a `filter` (or a
  # preparation) on each read action instead would trigger Ash's "primary read
  # action has filters" compile warning on every resource using the extension.
  defp filter_read_actions(dsl_state, attribute) do
    Ash.Resource.Builder.add_preparation(
      dsl_state,
      Ash.Resource.Preparation.Builtins.build(filter: expr(is_nil(^ref(attribute))))
    )
  end

  defp soften_destroy_actions(dsl_state, attribute) do
    dsl_state
    |> Transformer.get_entities([:actions])
    |> Enum.filter(&(&1.type == :destroy))
    |> Enum.reduce_while({:ok, dsl_state}, fn destroy, {:ok, dsl_state} ->
      set_archived_at =
        Ash.Resource.Change.Builtins.set_attribute(attribute, &DateTime.utc_now/0)

      case Ash.Resource.Builder.build_action_change(set_archived_at) do
        {:ok, change} ->
          archive = %{destroy | soft?: true, changes: [change | destroy.changes]}

          {:cont,
           {:ok,
            Transformer.replace_entity(
              dsl_state,
              [:actions],
              archive,
              &(&1.name == destroy.name)
            )}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end
end
