defmodule Twitter.ArchivalTest do
  use Twitter.DataCase, async: true

  alias Twitter.Tweets.Tweet

  # A throwaway resource to show the extension works on its own, with the
  # archive attribute renamed through the DSL.
  defmodule Note do
    use Ash.Resource,
      domain: Twitter.ArchivalTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [Twitter.Archival]

    archive do
      attribute :deleted_at
    end

    attributes do
      uuid_primary_key :id
      attribute :body, :string, public?: true
    end

    actions do
      defaults [:read, :destroy, create: [:body]]
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource Twitter.ArchivalTest.Note
    end
  end

  describe "the DSL rewrite" do
    test "adds a private archive attribute with a configurable name" do
      assert Twitter.Archival.Info.archive_attribute!(Tweet) == :archived_at

      assert %{type: Ash.Type.UtcDatetimeUsec, public?: false, allow_nil?: true} =
               Ash.Resource.Info.attribute(Tweet, :archived_at)

      assert Twitter.Archival.Info.archive_attribute!(Note) == :deleted_at
      assert Ash.Resource.Info.attribute(Note, :deleted_at)
      refute Ash.Resource.Info.attribute(Note, :archived_at)
    end

    test "turns every destroy action, including the default one, into a soft destroy" do
      destroys = Enum.filter(Ash.Resource.Info.actions(Tweet), &(&1.type == :destroy))
      assert [_ | _] = destroys

      for destroy <- destroys do
        assert destroy.soft?

        assert Enum.any?(destroy.changes, fn
                 %{change: {Ash.Resource.Change.SetAttribute, opts}} ->
                   opts[:attribute] == :archived_at

                 _ ->
                   false
               end)
      end
    end

    test "adds a resource-wide filter preparation" do
      assert Enum.any?(
               Ash.Resource.Info.preparations(Tweet),
               &match?(%{preparation: {Ash.Resource.Preparation.Build, _}}, &1)
             )
    end
  end

  describe "at runtime" do
    setup do
      user =
        Ash.Seed.seed!(Twitter.Accounts.User, %{
          email: "archivist-#{System.unique_integer([:positive])}@example.com",
          hashed_password: "not-used-in-tests"
        })

      %{user: user}
    end

    test "destroyed tweets disappear from every read but stay in the table", %{user: user} do
      kept = Ash.create!(Tweet, %{text: "kept"}, action: :create, actor: user)
      gone = Ash.create!(Tweet, %{text: "gone"}, action: :create, actor: user)

      assert :ok = Ash.destroy!(gone, actor: user)

      assert [%{id: id}] = Ash.read!(Tweet, actor: user)
      assert id == kept.id
      assert [%{id: ^id}] = Twitter.Tweets.feed!(actor: user)
      assert {:ok, nil} = Ash.get(Tweet, gone.id, actor: user, not_found_error?: false)

      assert %DateTime{} = Twitter.Repo.get!(Tweet, gone.id).archived_at
      assert is_nil(Twitter.Repo.get!(Tweet, kept.id).archived_at)
    end

    test "archived tweets are not loaded through relationships either", %{user: user} do
      tweet = Ash.create!(Tweet, %{text: "liked, then gone"}, action: :create, actor: user)
      like = Twitter.Tweets.like!(tweet.id, actor: user)

      assert %{tweet: %Tweet{}} = Ash.load!(like, :tweet, actor: user)

      Ash.destroy!(tweet, actor: user)

      assert %{tweet: nil} = Ash.load!(like, :tweet, actor: user)
    end

    test "works with a renamed attribute on an ETS resource" do
      note = Ash.create!(Note, %{body: "remember"})
      assert :ok = Ash.destroy!(note)

      assert Ash.read!(Note) == []
    end
  end
end
