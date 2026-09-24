defmodule Account do
  use Ash.Domain, otp_app: :twitter

  resources do
    resource Account.Profile do
      define :create_profile, args: [:name], action: :create
    end

    resource Account.Person
  end
end
