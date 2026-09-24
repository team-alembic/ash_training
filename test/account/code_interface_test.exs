defmodule Account.CodeInterfaceTest do
  use ExUnit.Case, async: false

  setup do
    Ash.DataLayer.Ets.stop(Account.Profile)
    :ok
  end

  describe "08_code_interfaces slide sequence" do
    test "create_profile! builds a profile from a bare name argument" do
      assert %Account.Profile{name: "José Valim"} = Account.create_profile!("José Valim")
    end
  end
end
