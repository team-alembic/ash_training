defmodule Account.ProfileTest do
  use ExUnit.Case, async: false

  require Ash.Query

  setup do
    Ash.DataLayer.Ets.stop(Account.Profile)

    Account.Profile
    |> Ash.Changeset.for_create(:create, %{name: "Joe Armstrong"})
    |> Ash.create!()

    profile =
      Account.Profile
      |> Ash.Changeset.for_create(:create, %{name: "Mike Williams"})
      |> Ash.create!()

    Account.Profile
    |> Ash.Changeset.for_create(:create, %{name: "Bjarne Däcker"})
    |> Ash.create!()

    %{profile: profile}
  end

  describe "03_actions slide sequence" do
    test "creating a profile with a name succeeds" do
      assert %Account.Profile{name: "My Name"} =
               Account.Profile
               |> Ash.Changeset.for_create(:create, %{name: "My Name"})
               |> Ash.create!()
    end

    test "creating a profile without a name raises with only the required-name error" do
      error =
        assert_raise Ash.Error.Invalid, fn ->
          Account.Profile
          |> Ash.Changeset.for_create(:create, %{})
          |> Ash.create!()
        end

      assert [%Ash.Error.Changes.Required{field: :name}] = error.errors
    end

    test "reading all profiles returns every created profile", %{profile: _profile} do
      Account.Profile
      |> Ash.Changeset.for_create(:create, %{name: "My Name"})
      |> Ash.create!()

      assert length(Ash.read!(Account.Profile)) == 4
    end

    test "filtering by name returns the matching profile" do
      assert [%Account.Profile{name: "Joe Armstrong"}] =
               Account.Profile
               |> Ash.Query.filter(name == "Joe Armstrong")
               |> Ash.read!()
    end

    test "sorting by created_at desc with a limit returns the most recently created profile" do
      newest =
        Account.Profile
        |> Ash.Changeset.for_create(:create, %{name: "My Name"})
        |> Ash.create!()

      assert %Account.Profile{id: id} =
               Account.Profile
               |> Ash.Query.sort(created_at: :desc)
               |> Ash.Query.limit(1)
               |> Ash.read_one!()

      assert id == newest.id
    end

    test "updating a profile changes its name", %{profile: profile} do
      assert %Account.Profile{name: "Robert Virding"} =
               profile
               |> Ash.Changeset.for_update(:update, %{name: "Robert Virding"})
               |> Ash.update!()
    end

    test "destroying a profile returns :ok", %{profile: profile} do
      assert :ok =
               profile
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy!()
    end

    test "say_hello returns a greeting built from the argument" do
      assert "Hello: Joe" =
               Account.Profile
               |> Ash.ActionInput.for_action(:say_hello, %{name: "Joe"})
               |> Ash.run_action!()
    end
  end

  describe "05_advanced_actions slide sequence" do
    test "the latest read action sorts by created_at desc" do
      assert [%Account.Profile{name: "Bjarne Däcker"}, _, _] =
               Account.Profile
               |> Ash.Query.for_read(:latest)
               |> Ash.read!()
    end

    test "publish sets the status to :published" do
      profile =
        Account.Profile
        |> Ash.Query.filter(name == "Joe Armstrong")
        |> Ash.read_one!()

      assert %Account.Profile{status: :published} =
               profile
               |> Ash.Changeset.for_update(:publish)
               |> Ash.update!()
    end

    test "duplicate names are rejected by the profile_name identity" do
      assert_raise Ash.Error.Invalid, fn ->
        Account.Profile
        |> Ash.Changeset.for_create(:create, %{name: "Joe Armstrong"})
        |> Ash.create!()
      end
    end

    test "get by identity fields fetches a profile by name" do
      assert %Account.Profile{name: "Joe Armstrong"} =
               Ash.get!(Account.Profile, %{name: "Joe Armstrong"})
    end

    test "create_or_publish upserts an existing profile and reports the update branch" do
      record =
        Account.Profile
        |> Ash.Changeset.for_create(:create_or_publish, %{name: "Joe Armstrong"})
        |> Ash.create!()

      assert record.status == :published
      assert Ash.Resource.get_metadata(record, :upsert_action) == :update
    end

    test "create_or_publish inserts a new profile when the name doesn't exist yet" do
      record =
        Account.Profile
        |> Ash.Changeset.for_create(:create_or_publish, %{name: "Grace Hopper"})
        |> Ash.create!()

      assert record.status == :published
      assert Ash.Resource.get_metadata(record, :upsert_action) == :create
    end
  end
end
