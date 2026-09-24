defmodule Twitter.Archival do
  @moduledoc """
  Soft-deletes for Ash resources: a bare-bones `AshArchival`.

  Adding this extension to a resource

    * adds an `archived_at` attribute (`nil` = live, a timestamp = archived),
    * makes every read action skip archived records, and
    * turns every destroy action into an update that stamps `archived_at`.

  The attribute can be renamed with the `archive` section:

      use Ash.Resource, extensions: [Twitter.Archival]

      archive do
        attribute :deleted_at
      end
  """

  @archive %Spark.Dsl.Section{
    name: :archive,
    describe: "Configure how records of this resource are archived instead of destroyed.",
    examples: [
      """
      archive do
        attribute :deleted_at
      end
      """
    ],
    schema: [
      attribute: [
        type: :atom,
        default: :archived_at,
        doc: "The attribute that records when a record was archived. `nil` means it is live."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@archive],
    transformers: [Twitter.Archival.Transformers.SetupArchival]
end
