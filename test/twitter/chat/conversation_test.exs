defmodule Twitter.Chat.ConversationTest do
  use Twitter.DataCase, async: true
  use Oban.Testing, repo: Twitter.Repo

  test "the naming scheduler picks up conversations that need a title" do
    user =
      Ash.Seed.seed!(Twitter.Accounts.User, %{
        email: "chat@example.com",
        hashed_password: "not-used-in-tests"
      })

    message = Twitter.Chat.create_message!(%{text: "hello"}, actor: user)

    for text <- ["two", "three", "four"] do
      Ash.Seed.seed!(Twitter.Chat.Message, %{
        conversation_id: message.conversation_id,
        text: text
      })
    end

    AshOban.schedule(Twitter.Chat.Conversation, :name_conversation)
    Oban.drain_queue(queue: :conversations, with_recursion: false)

    assert_enqueued worker: Twitter.Chat.Message.Workers.NameConversation,
                    args: %{"primary_key" => %{"id" => message.conversation_id}}
  end
end
