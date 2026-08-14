defmodule Twitter.Accounts.User do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication, AshAdmin.Resource],
    authorizers: [Ash.Policy.Authorizer],
    domain: Twitter.Accounts

  resource do
    description "A user of the app. A user's email is only visible to that user."
  end

  admin do
    actor? true
  end

  postgres do
    table "users"
    repo Twitter.Repo
  end

  authentication do
    strategies do
      password :password do
        identity_field :email
      end

      api_key :api_key do
        api_key_relationship :valid_api_keys
        api_key_hash_attribute :api_key_hash
      end
    end

    tokens do
      enabled? true
      token_resource Twitter.Accounts.Token
      signing_secret Twitter.Accounts.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :email do
      authorize_if expr(id == ^actor(:id))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end
  end

  actions do
    defaults [:read]

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  relationships do
    has_many :valid_api_keys, Twitter.Accounts.ApiKey do
      filter expr(valid)
    end
  end
end
