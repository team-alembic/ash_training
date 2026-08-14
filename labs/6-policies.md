# Lab 6 - Policies

- [Actors & Authorization](https://hexdocs.pm/ash/actors-and-authorization.html)
- [Policies](https://hexdocs.pm/ash/policies.html)

## Existing Setup

- User has policy for allowing `AshAuthentication` to do whatever it wants
- User has policy for allowing anyone to read any user

## Steps

1. Add the `Ash.Policy.Authorizer` authorizer to `Tweet`.

```sh
mix ash.extend Twitter.Tweets.Tweet Ash.Policy.Authorizer
```

2. Add a policy for `action_type(:read)` on tweets.

```elixir
policies do
  policy action_type(:read) do
    authorize_if always()
  end
end
```

3. Now we can read tweets, but can't create or update them. Feel free to try it out.
   Let's add a policy allowing any user to create a tweet.

```elixir
policy action(:create) do
  authorize_if always()
end
```

4. We can read and create tweets now, but what happens if we update/destroy them?
   Try it out and see. (check the logs — setting `config :ash, show_policy_breakdowns?: true`
   gives you a full breakdown of which policy failed and why)

Add policies allowing the author of the tweet to update/destroy. We can also give the
policy a custom `error_message`, which is used when this policy is the one responsible
for the `Forbidden` error — much friendlier than the default.

```elixir
policy action([:update, :destroy]) do
  error_message "only the author can edit or delete a tweet"
  authorize_if expr(user_id == ^actor(:id))
end
```

The existing tests in `test/twitter/tweets/tweet_test.exs` call `Ash.update!`
and `Ash.destroy!` without an actor, so they now fail with a `Forbidden` error.
Pass `actor: user` to those calls to fix them.

5. Now we've got appropriate policies set up for tweets, but the UI still looks like we can delete or edit other user's tweets.

To test this, open an incognito window, create another user, and try to edit/delete an existing tweet.

Let's add some checks to the UI to make sure we only show the edit/delete buttons for the right user.

Wrap our edit/delete buttons in an `if` block that checks if the current user can perform the action.

```elixir
<%= if Ash.can?({tweet, :update}, @current_user) do %>

<% end %>


<%= if Ash.can?({tweet, :destroy}, @current_user) do %>

<% end %>
```

Since we're checking two permissions on the same tweet, we can also batch them into a
single call with `Ash.can_do_all?`, which shares the actor across all the checks:

```elixir
Ash.can_do_all?([{tweet, :update}, {tweet, :destroy}], @current_user)
```

There's also `Ash.can_do_all/3`, which takes named checks and returns
`{:ok, results}` where `results` is a map keyed by your check names — handy when
you want each button to check its own permission in one go.

Apply the same update check to the edit button in `show.ex`. In `form.ex`, check
the loaded tweet with `Ash.can?/2` in `apply_action` and redirect unauthorized
users before showing the edit form (e.g. `put_flash` an error and
`push_navigate` back to the tweet's show page). Hiding a button improves the UX;
the resource policy is still the security boundary.

6. Now let's add some policies to the user resource. We start off with some builtin policies
   recommended by AshAuthentication, as well as a blanket policy allowing anyone to read all users.
   This isn't ideal, so let's add a policy to only allow users to read themselves.

```elixir
policy action_type(:read) do
  authorize_if expr(id == ^actor(:id))
end
```

(This trips another test: `Ash.load!(tweet, :user)` now needs `actor: user`
too.)

7. You'll see that if you load the tweets page, you can no longer see the email of the user who tweeted, unless it is yourself!

This is a great example of how Ash helps you apply policies _everywhere_ in your app, even places that are commonly overlooked.

8. However, this is not the UX we want, because we still want to be able to see the email of the author of a tweet.
   So let's add the `authorize? false` option to the `user_email` aggregate on tweet.

```elixir
first :user_email, :user, :email do
  authorize? false
end
```

`authorize? false` deliberately bypasses the related user's read policy. That
is acceptable for this training example because author email is intentionally
public in the feed, but avoid this for sensitive fields in a real application.

9. Our read policy hides the _whole_ user record just to protect one field. The idiomatic
   way to hide a single attribute is a [field policy](https://hexdocs.pm/ash/policies.html#field-policies).
   Revert the read policy on `User` back to `authorize_if always()`, and instead add this to `User`:

```elixir
field_policies do
  field_policy :email do
    authorize_if expr(id == ^actor(:id))
  end

  field_policy :* do
    authorize_if always()
  end
end
```

Now other users are readable, but their `email` loads as `%Ash.ForbiddenField{}` unless
it's your own. Note that the feed still shows author emails either way:
[aggregates authorize access to the related records they reference, but never to
the field itself](https://hexdocs.pm/ash/policies.html#aggregates), so the
`User` field policy doesn't apply to the tweet's `user_email` aggregate. The
`authorize? false` on the aggregate only skips the related user's _read
policies_ — that's what steps 7–8 needed, but now that the read policy is back
to `authorize_if always()`, removing it changes nothing visible. Keep it anyway:
it documents that this aggregate must stay exempt if `User` read policies ever
tighten again.

## Try on your own

- Generate policy flow charts with `mix ash.generate_policy_charts --all`. The default format writes a `*-policy-flowchart.mmd` file next to each resource, e.g. `lib/twitter/tweets/tweet-policy-flowchart.mmd` — look there for the output, and don't commit these files. You can add the `--format png` option, but that requires `npm install -g @mermaid-js/mermaid-cli`, which people tend to have issues with due to node versions. To view the charts otherwise, paste the mermaid code into the [Mermaid Live Editor](https://mermaid.live/edit)

- Add an attribute on tweets called `:private`. Add a checkbox to the UI for it. Only show private tweets to users who are the author of the tweet. (New attributes need a migration: `mix ash.codegen add_private_to_tweets`, then `mix ash.migrate` — same goes for the flags in the bullets below.)

```elixir
<.input label="Private" type="checkbox" name="tweet[private]" value={@tweet && @tweet.private} />
```

- Add a flag on users called `:disabled`, and a policy on tweets that prevents them from reading tweets. See what happens when you log in as one of these users (to set the flag you'll need an update action on `User` that accepts `:disabled`, and you'll have to call it in `iex` with `authorize?: false`, since `User`'s policies won't let you through)

- Add a flag on users called `:admin`, and a [bypass](https://hexdocs.pm/ash/policies.html#bypass-policies) on tweets that allows users to read any tweet if they are an admin. If you end up with several admin-only policies, try grouping them with a [policy group](https://hexdocs.pm/ash/policies.html#policy-groups): `policy_group actor_attribute_equals(:admin, true) do ... end`. Note that a policy group can _not_ contain bypasses, and it isn't one itself — the policies inside still combine with all your other applicable policies — so keep the admin bypass as a bypass and use the group only for additional admin-only policies.
