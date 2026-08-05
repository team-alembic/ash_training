defmodule Twitter.Chat.Conversation do
  use Ash.Resource,
    otp_app: :twitter,
    domain: Twitter.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :messages, Twitter.Chat.Message do
      public? true
    end

    belongs_to :user, Twitter.Accounts.User do
      public? true
      allow_nil? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title]
      change relate_actor(:user)
    end

    update :generate_name do
      accept []
      transaction? false
      require_atomic? false
      change Twitter.Chat.Conversation.Changes.GenerateName
    end

    read :my_conversations do
      filter expr(user_id == ^actor(:id))
    end
  end

  policies do
    bypass action(:generate_name) do
      authorize_if AshOban.Checks.AshObanInteraction
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action(:destroy) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  postgres do
    table "conversations"
    repo Twitter.Repo
  end

  calculations do
    calculate :needs_title, :boolean do
      calculation expr(
                    is_nil(title) and
                      (count(messages) > 3 or
                         (count(messages) > 1 and inserted_at < ago(10, :minute)))
                  )
    end
  end

  pub_sub do
    module TwitterWeb.Endpoint
    prefix "chat"

    publish_all :create, ["conversations", :user_id] do
      transform & &1.data
    end

    publish_all :update, ["conversations", :user_id] do
      transform & &1.data
    end
  end

  oban do
    triggers do
      trigger :name_conversation do
        action :generate_name
        queue :conversations
        lock_for_update? false
        scheduler_cron false
        worker_module_name Twitter.Chat.Message.Workers.NameConversation
        scheduler_module_name Twitter.Chat.Message.Schedulers.NameConversation
        where expr(needs_title)
      end
    end
  end
end
