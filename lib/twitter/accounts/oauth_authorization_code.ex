defmodule Twitter.Accounts.OauthAuthorizationCode do
  use Ash.Resource,
    otp_app: :twitter,
    domain: Twitter.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.Oauth2Server.AuthorizationCodeResource],
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_v7_primary_key :id

    attribute :client_id, :uuid_v7 do
      allow_nil? false
      public? true
    end

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :redirect_uri, :string do
      allow_nil? false
      public? true
    end

    attribute :code_challenge, :string do
      allow_nil? false
      public? true
    end

    attribute :scope, :string do
      allow_nil? false
      public? true
    end

    attribute :resource_uri, :string do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :consumed_at, :utc_datetime_usec do
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :client_id,
        :user_id,
        :redirect_uri,
        :code_challenge,
        :scope,
        :resource_uri,
        :expires_at
      ]
    end

    update :consume do
      accept []

      validate absent(:consumed_at) do
        message "code already used"
      end

      change atomic_update(:consumed_at, expr(now()))
    end
  end

  postgres do
    table "oauth_authorization_codes"
    repo Twitter.Repo
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end
end
