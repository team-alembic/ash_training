defmodule Twitter.Accounts do
  use Ash.Domain,
    otp_app: :twitter,
    extensions: [AshAdmin.Domain, AshLua.Domain]

  admin do
    show? true
  end

  lua do
    namespace "users" do
      action :list, Twitter.Accounts.User, :read, labels: [:agent, :read_only]
    end
  end

  resources do
    resource Twitter.Accounts.User
    resource Twitter.Accounts.Token
    resource Twitter.Accounts.ApiKey
  end
end
