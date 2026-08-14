defmodule Twitter.Accounts.OauthConsent do
  use Ash.Resource,
    otp_app: :twitter,
    domain: Twitter.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_v7_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :client_id, :uuid_v7 do
      allow_nil? false
      public? true
    end

    attribute :scope, :string do
      allow_nil? false
      public? true
    end

    attribute :granted_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :grant do
      upsert? true
      upsert_identity :by_user_client
      accept [:user_id, :client_id, :scope]
      change set_attribute(:granted_at, &DateTime.utc_now/0)
    end
  end

  postgres do
    table "oauth_consents"
    repo Twitter.Repo
  end

  identities do
    identity :by_user_client, [:user_id, :client_id]
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end
end
