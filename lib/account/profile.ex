defmodule Account.Profile do
  use Ash.Resource,
    otp_app: :twitter,
    domain: Account,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read, :destroy, create: [:name], update: [:name]]

    read :latest do
      prepare build(sort: [created_at: :desc])
    end

    update :publish do
      accept []
      # The `profile_name` identity's pre_check? runs as a before_action hook
      # on every update, which Ash can't fold into an atomic update.
      require_atomic? false

      change set_attribute(:status, :published)
      validate string_length(:name, min: 2, max: 255)
    end

    action :say_hello, :string do
      argument :name, :string, allow_nil?: false

      run fn input, _ ->
        {:ok, "Hello: #{input.arguments.name}"}
      end
    end

    create :create_or_publish do
      accept [:name]

      change set_attribute(:status, :published)
      upsert? true
      upsert_identity :profile_name
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:unpublished, :published]
      default :unpublished
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    # ETS has no native unique constraint enforcement, so pre_check? runs the
    # uniqueness check in a before_action hook via the resource's domain.
    identity :profile_name, [:name] do
      pre_check? true
    end
  end
end
