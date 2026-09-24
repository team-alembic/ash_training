defmodule Account.PersonTest do
  use ExUnit.Case, async: false

  require Ash.Query

  setup do
    Ash.DataLayer.Ets.stop(Account.Person)

    Account.Person
    |> Ash.Changeset.for_create(:create, %{first_name: "Joe", last_name: "Armstrong"})
    |> Ash.create!()

    :ok
  end

  describe "06_calculations_aggregates slide sequence" do
    test "filtering on the full_name calculation returns the matching person" do
      assert [%Account.Person{first_name: "Joe", last_name: "Armstrong"}] =
               Account.Person
               |> Ash.Query.filter(full_name == "Joe Armstrong")
               |> Ash.read!()
    end

    test "calculating full_name in memory concatenates first and last name" do
      person = %Account.Person{first_name: "Joe", last_name: "Armstrong"}

      assert Ash.calculate!(person, :full_name) == "Joe Armstrong"
    end

    test "creating a person leaves full_name not loaded" do
      person =
        Account.Person
        |> Ash.Changeset.for_create(:create, %{first_name: "Joe", last_name: "Armstrong"})
        |> Ash.create!()

      assert %Ash.NotLoaded{} = person.full_name
    end

    test "creating a person and loading full_name calculates it" do
      person =
        Account.Person
        |> Ash.Changeset.for_create(:create, %{first_name: "Joe", last_name: "Armstrong"})
        |> Ash.create!()
        |> Ash.load!([:full_name])

      assert person.full_name == "Joe Armstrong"
    end
  end
end
