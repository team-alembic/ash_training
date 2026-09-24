require Ash.Query

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

Account.Person
|> Ash.Changeset.for_create(:create, %{first_name: "Joe", last_name: "Armstrong"})
|> Ash.create!()

IO.puts(
  "Seeded 3 Account.Profile records (Joe Armstrong, Mike Williams, Bjarne Däcker) and 1 Account.Person (Joe Armstrong); `profile` is bound to Mike Williams."
)
