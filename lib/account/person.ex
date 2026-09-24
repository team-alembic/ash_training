defmodule Account.Person do
  use Ash.Resource,
    otp_app: :twitter,
    domain: Account,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]

    create :create do
      accept [:first_name, :last_name]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :first_name, :string do
      allow_nil? false
    end

    attribute :last_name, :string do
      allow_nil? false
    end
  end

  calculations do
    calculate :full_name, :string, expr(first_name <> " " <> last_name)
  end
end
