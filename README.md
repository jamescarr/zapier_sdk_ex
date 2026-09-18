# ZapierSDK

[![Hex.pm](https://img.shields.io/hexpm/v/zapier_sdk.svg)](https://hex.pm/packages/zapier_sdk)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/zapier_sdk)

**Unofficial** Elixir SDK for the [Zapier SDK](https://docs.zapier.com/sdk). Run
Zapier actions — search, read, write — against any of Zapier's 9,000+
integrations directly from the BEAM, with concurrency, streaming, and telemetry
built in.

This is a native HTTP client. There is **no Node.js, npm package, or CLI**
involved at runtime: it talks to the [Zapier SDK API](https://docs.zapier.com/sdk)
the same way the official TypeScript SDK does.

> The Zapier SDK is in open beta and free during early access. Enterprise
> accounts are opted out by default. See the
> [official docs](https://docs.zapier.com/sdk) for current status.

## Installation

```elixir
def deps do
  [
    {:zapier_sdk, "~> 0.2"}
  ]
end
```

## Authentication

The SDK authenticates with OAuth client credentials, the same mechanism the
official SDK uses to run [without a browser login](https://docs.zapier.com/sdk/deploy).
Create a pair once with the [Zapier SDK CLI](https://www.npmjs.com/package/@zapier/zapier-sdk-cli):

```bash
npx @zapier/zapier-sdk-cli login
npx @zapier/zapier-sdk-cli create-client-credentials
```

The client secret is shown **once**, at creation. Then configure it:

```elixir
config :zapier_sdk,
  client_id: System.get_env("ZAPIER_CREDENTIALS_CLIENT_ID"),
  client_secret: System.get_env("ZAPIER_CREDENTIALS_CLIENT_SECRET")
```

If `:client_id` and `:client_secret` are unset, the SDK falls back to the
`ZAPIER_CREDENTIALS_CLIENT_ID` and `ZAPIER_CREDENTIALS_CLIENT_SECRET`
environment variables. Tokens are fetched on first use and refreshed
automatically before they expire.

These are the same variable names the official SDK reads, so an environment
already set up for it works here unchanged. Zapier's
[deploy guide](https://docs.zapier.com/sdk/deploy) covers storing them on
Railway, Vercel, GitHub Actions, GitLab CI, and AWS, plus rotation.

For a short-lived script you can supply a bearer token directly with
`config :zapier_sdk, token: "..."` (or `ZAPIER_CREDENTIALS`). It is never
refreshed.

## Connections

A *connection* is an authenticated link between your Zapier account and a
third-party app. Every action runs in the context of one. Connection IDs are
UUIDs — find yours with:

```elixir
{:ok, connections} = ZapierSDK.list_connections()

Enum.each(connections, fn c ->
  IO.puts("#{c["id"]}  #{c["app_key"]}  #{c["title"]}")
end)
```

Register the ones you use regularly so you can refer to them by name:

```elixir
config :zapier_sdk, connections: [
  drive:    {"google-drive",        "00000000-0000-0000-0000-000000000000"},
  slack:    {"slack",               "00000000-0000-0000-0000-000000000000"},
  jira:     {"jira-software-cloud", "00000000-0000-0000-0000-000000000000"},
  calendar: {"google-calendar",     "00000000-0000-0000-0000-000000000000"}
]
```

Or build one inline, no config required:

```elixir
conn = ZapierSDK.connection("google-drive", "02069fbe-9c91-81c1-8567-8ee2dbb7ad64")
{:ok, result} = ZapierSDK.search(conn, "file_v2", %{"title" => "budget"})
```

## Quick start

```elixir
# Search Google Drive
{:ok, result} = ZapierSDK.search(:drive, "file_v2", %{"title" => "Q3 budget"})

for file <- result do
  IO.puts(file["title"])
end

# Post to Slack
{:ok, _} = ZapierSDK.write(:slack, "channel_message", %{
  "channel" => "#engineering",
  "text" => "Deploy complete"
})
```

Actions have a *type* (`:search`, `:read`, `:write`, and a few others) that is
part of their identity — Zapier exposes distinct `search` and `write` actions
under the same key, and the API rejects a mismatch. Use the helper that matches:
`search/4`, `read/4`, or `write/4`.

## Discovering actions and inputs

```elixir
{:ok, apps}    = ZapierSDK.list_apps(search: "google")
{:ok, actions} = ZapierSDK.list_actions("google-drive", action_type: "search")
```

If you get an action key wrong, the error lists the valid ones:

```elixir
{:error, error} = ZapierSDK.search(:drive, "find_file", %{})
error.type     #=> :action_not_found
error.details  #=> ["file_or_folder_by_id", "file_permissions", "file_v2", "folder_v2"]
```

## Error handling

Nothing raises. Every call returns `{:ok, %Result{}}` or
`{:error, %ZapierSDK.Error{}}`, and you can match on `error.type`:

```elixir
case ZapierSDK.search(:jira, "issue_key", %{"issue_key" => "PROJ-1"}) do
  {:ok, result} ->
    result.data

  {:error, %ZapierSDK.Error{type: :connection_expired}} ->
    # The app's OAuth grant lapsed — reconnect it in Zapier.
    :needs_reconnect

  {:error, %ZapierSDK.Error{type: :rate_limited} = error} ->
    Process.sleep(error.retry_after_ms || 1_000)
    :retry

  {:error, error} ->
    Logger.error(Exception.message(error))
end
```

A run that finishes with integration errors is an **error**, not an empty
success. An expired Jira connection gives you
`%Error{type: :connection_expired}`, not `{:ok, %Result{count: 0}}`.

| `type` | Meaning |
|---|---|
| `:no_credentials` | Nothing configured to authenticate with |
| `:authentication_failed` | Token exchange rejected, or the API returned 401 |
| `:connection_expired` | The app connection needs reconnecting |
| `:action_failed` | The integration returned errors |
| `:app_not_found` / `:action_not_found` | Unknown app or action key |
| `:rate_limited` | 429; see `:retry_after_ms` |
| `:timeout` | The run did not finish in time |
| `:http_error` / `:transport_error` | Other HTTP or network failure |

## Concurrency

Actions run in the caller's process, so concurrency is just a matter of
starting more of them.

```elixir
# Off the current process
task = ZapierSDK.async(:drive, :search, "file_v2", %{"title" => "notes"})
{:ok, result} = Task.await(task, 60_000)

# Several at once, results in input order
alias ZapierSDK.Action

results = ZapierSDK.run_many([
  {:drive, Action.search("file_v2", %{"title" => "notes"})},
  {:slack, Action.search("message", %{"query" => "deploy"})}
], max_concurrency: 4)

Enum.each(results, fn
  {:ok, result} -> IO.puts("#{result.count} items in #{result.elapsed_ms}ms")
  {:error, err} -> IO.puts("failed: #{Exception.message(err)}")
end)
```

## Pagination and streaming

`run/3` follows Zapier's `next_page` cursor and returns every page. Cap it with
`:max_items`:

```elixir
{:ok, result} = ZapierSDK.search(:drive, "file_v2", %{"title" => "report"}, max_items: 50)
```

Or stream, which fetches pages lazily so `Stream.take/2` stops early:

```elixir
ZapierSDK.stream(:drive, "file_v2", %{"title" => "report"})
|> Stream.take(5)
|> Enum.each(&IO.inspect/1)
```

Streams raise `ZapierSDK.Error` on failure, since there is nowhere to return an
error tuple. Use `search/4` when you would rather match on one.

## App helpers

Typed wrappers over the actions and input fields of a few common integrations:

```elixir
alias ZapierSDK.Apps.{GoogleDrive, Slack, GoogleCalendar, Jira, Coda}

{:ok, result} = GoogleDrive.find_file("Q3 budget")
{:ok, _}      = Slack.send_message("#general", "Hello!")
{:ok, result} = GoogleCalendar.today_events()
{:ok, result} = Jira.my_open_issues()
{:ok, rows}   = Coda.list_rows(doc_id, table_id)
```

Each module reads a default named connection (`:drive`, `:slack`, `:calendar`,
`:jira`, `:coda`); override per call with `connection:`.

## Telemetry

Events are emitted under the `[:zapier_sdk, :action]` prefix:

| Event | Measurements | Metadata |
|---|---|---|
| `[:zapier_sdk, :action, :start]` | `system_time` | `connection`, `action` |
| `[:zapier_sdk, :action, :stop]` | `duration` | `connection`, `action`, `result` |
| `[:zapier_sdk, :action, :exception]` | `duration` | `connection`, `action`, `kind`, `reason` |

A returned `{:error, _}` is a `:stop` event whose `:result` is the error tuple,
not an `:exception` — handlers counting failures should match on the result.

```elixir
:telemetry.attach("log-zapier", [:zapier_sdk, :action, :stop], fn _e, %{duration: d}, meta, _ ->
  ms = System.convert_time_unit(d, :native, :millisecond)
  Logger.info("#{meta.action.name} finished in #{ms}ms")
end, nil)
```

## Testing

The SDK runs every request through `Req`, so tests can stub the transport with
`Req.Test` and never touch the network:

```elixir
# config/test.exs
config :zapier_sdk,
  req_options: [plug: {Req.Test, ZapierSDK}],
  token: "test-token",
  max_retries: 0
```

```elixir
test "finds a file" do
  Req.Test.stub(ZapierSDK, fn conn ->
    # ...respond to /api/v0/apps, /api/v0/actions, and the run endpoints
  end)

  assert {:ok, result} = ZapierSDK.search(:drive, "file_v2", %{"title" => "x"})
  assert result.count == 1
end
```

This project's own suite uses `ZapierSDK.ZapierStub`, which implements the full
protocol so tests describe outcomes rather than individual responses.

## How it works

Running an action is a two-phase protocol, which the SDK hides behind one call:

1. Resolve the app's versioned `implementation_id` and the action's internal
   ID (cached in ETS, since they only change when an app publishes).
2. `POST` an action run, then poll it with backoff until it leaves the
   `waiting` state, following `next_page` for as long as you want results.

```
ZapierSDK              ← Public API
├── Client             ← Action runs: create, poll, paginate
├── Catalog            ← App/action/connection metadata + ETS cache
├── Auth               ← OAuth client credentials, token cache + refresh
├── HTTP               ← Req transport, error mapping, retry policy
├── Connection         ← Named and ad-hoc connections
├── Action             ← Action structs and types
├── Result             ← Results (implements Enumerable)
├── Error              ← Typed errors
├── Config             ← Config and environment resolution
└── Apps/              ← Jira, Slack, GoogleDrive, GoogleCalendar, Coda
```

Only idempotent requests are retried. An action-run `POST` is never replayed —
retrying "send a Slack message" would send it twice — and a 429 is surfaced
with `:retry_after_ms` rather than slept on inside the call.

## Zapier's documentation

This library is unofficial and not affiliated with Zapier. For the underlying
platform:

| Link | What's there |
|---|---|
| [Zapier SDK](https://docs.zapier.com/sdk) | Landing page, beta status, concepts |
| [Quickstart](https://docs.zapier.com/sdk/quickstart) | The official TypeScript walkthrough |
| [API reference](https://docs.zapier.com/sdk/reference) | Every SDK method and its arguments |
| [CLI reference](https://docs.zapier.com/sdk/cli-reference) | `list-apps`, `list-actions`, `list-input-fields`, and friends |
| [Deploy with client credentials](https://docs.zapier.com/sdk/deploy) | Creating, storing, and rotating credentials |
| [Your connections](https://zapier.com/app/assets/connections) | Connect apps and fix expired ones |

App keys, action keys, and input field names are shared across every Zapier
client, so the CLI is the fastest way to discover what to pass here:

```bash
npx @zapier/zapier-sdk-cli list-actions google-drive --action-type search
npx @zapier/zapier-sdk-cli list-input-fields google-drive search file_v2
```

`ZapierSDK.list_apps/1` and `ZapierSDK.list_actions/2` expose the same catalog
from Elixir if you would rather stay in the REPL.

## License

MIT
