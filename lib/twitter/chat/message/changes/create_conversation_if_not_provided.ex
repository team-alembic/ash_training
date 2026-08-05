defmodule Twitter.Chat.Message.Changes.CreateConversationIfNotProvided do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    if changeset.arguments[:conversation_id] do
      conversation =
        Twitter.Chat.get_conversation!(
          changeset.arguments.conversation_id,
          Ash.Context.to_opts(context)
        )

      Ash.Changeset.force_change_attribute(
        changeset,
        :conversation_id,
        conversation.id
      )
    else
      Ash.Changeset.before_action(changeset, fn changeset ->
        conversation = Twitter.Chat.create_conversation!(Ash.Context.to_opts(context))

        Ash.Changeset.force_change_attribute(changeset, :conversation_id, conversation.id)
      end)
    end
  end
end
