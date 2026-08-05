defmodule TwitterWeb.GraphqlTweetTest do
  use TwitterWeb.ConnCase, async: true

  test "queries the generated tweet feed", %{conn: conn} do
    user =
      Ash.Seed.seed!(Twitter.Accounts.User, %{
        email: "graphql@example.com",
        hashed_password: "not-used-in-tests"
      })

    tweet =
      Ash.create!(Twitter.Tweets.Tweet, %{text: "from GraphQL"},
        action: :create,
        actor: user
      )

    query = """
    query {
      feed {
        id
        text
        likeCount
        userEmail
      }
    }
    """

    conn = post(conn, "/api/gql", %{query: query})

    assert %{
             "data" => %{
               "feed" => [
                 %{
                   "id" => id,
                   "text" => "from GraphQL",
                   "likeCount" => 0,
                   "userEmail" => email
                 }
               ]
             }
           } = json_response(conn, 200)

    assert id == tweet.id
    assert email == to_string(user.email)
  end
end
