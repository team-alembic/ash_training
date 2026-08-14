defmodule Twitter.Accounts do
  use Ash.Domain,
    otp_app: :twitter,
    extensions: [AshAdmin.Domain, AshLua.Domain]

  admin do
    show? true
  end

  resources do
    resource Twitter.Accounts.User
    resource Twitter.Accounts.Token
  end
end
