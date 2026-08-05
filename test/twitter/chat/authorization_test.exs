defmodule Twitter.Chat.AuthorizationTest do
  use Twitter.DataCase, async: true

  alias Twitter.Chat.Message

  test "conversations and message history are scoped to their owner" do
    owner = seed_user("chat-owner@example.com")
    other_user = seed_user("chat-other@example.com")
    conversation = Twitter.Chat.create_conversation!(actor: owner)

    Ash.Seed.seed!(Message, %{
      text: "private chat message",
      source: :user,
      conversation_id: conversation.id
    })

    assert Twitter.Chat.get_conversation!(conversation.id, actor: owner).id == conversation.id
    assert [message] = Twitter.Chat.message_history!(conversation.id, actor: owner)
    assert message.text == "private chat message"

    assert_raise Ash.Error.Invalid, fn ->
      Twitter.Chat.get_conversation!(conversation.id, actor: other_user)
    end

    assert Twitter.Chat.message_history!(conversation.id, actor: other_user) == []
  end

  test "a supplied conversation id is authorized during message creation" do
    owner = seed_user("conversation-owner@example.com")
    other_user = seed_user("conversation-intruder@example.com")
    conversation = Twitter.Chat.create_conversation!(actor: owner)

    assert_raise Ash.Error.Invalid, fn ->
      Message
      |> Ash.Changeset.for_create(:create, %{text: "intrusion"},
        actor: other_user,
        private_arguments: %{conversation_id: conversation.id}
      )
      |> Ash.create!()
    end
  end

  defp seed_user(email) do
    Ash.Seed.seed!(Twitter.Accounts.User, %{
      email: email,
      hashed_password: "not-used-in-tests"
    })
  end
end
