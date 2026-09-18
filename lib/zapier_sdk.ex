defmodule ZapierSDK do
  @moduledoc """
  Unofficial Elixir SDK for Zapier.

  Talks to the [Zapier SDK API](https://docs.zapier.com/sdk) over HTTP — there
  is no Node runtime, npm package, or CLI involved. Actions run concurrently on
  the BEAM, results stream, and every call emits telemetry.

  ## Setup

  Create a set of client credentials once (`npx @zapier/zapier-sdk-cli
  create-client-credentials`; see Zapier's
  [deploy guide](https://docs.zapier.com/sdk/deploy)) and configure them:

      config :zapier_sdk,
        client_id: System.get_env("ZAPIER_CREDENTIALS_CLIENT_ID"),
        client_secret: System.get_env("ZAPIER_CREDENTIALS_CLIENT_SECRET"),
        connections: [
          drive: {"google-drive", "02069fbe-9c91-81c1-8567-8ee2dbb7ad64"},
          slack: {"slack", "02217725-24ba-8453-b2c2-75f41bf95747"}
        ]

  `ZapierSDK.list_connections/1` prints the IDs available on your account.

  ## Running actions

      {:ok, result} = ZapierSDK.search(:drive, "file_v2", %{"title" => "Q3 budget"})

      for file <- result do
        IO.puts(file["title"])
      end

  Actions come in types (`:search`, `:read`, `:write`, ...) and the type is
  part of the action's identity, so use the matching helper:

      {:ok, _} = ZapierSDK.write(:slack, "channel_message", %{
        "channel" => "#engineering",
        "text" => "Deploy complete"
      })

  ## Concurrency

      # One action, off the current process
      task = ZapierSDK.async(:drive, :search, "file_v2", %{"title" => "notes"})
      {:ok, result} = Task.await(task, 60_000)

      # Several at once
      results = ZapierSDK.run_many([
        {:drive, Action.search("file_v2", %{"title" => "notes"})},
        {:slack, Action.search("message", %{"query" => "deploy"})}
      ], max_concurrency: 4)

  ## Errors

  Nothing raises on failure; you get `{:error, %ZapierSDK.Error{}}` with a
  `:type` you can match on. Note that a run which finishes with integration
  errors — an expired connection, say — is an error, not an empty success.

      case ZapierSDK.search(:drive, "file_v2", %{"title" => "x"}) do
        {:ok, result} -> result.data
        {:error, %ZapierSDK.Error{type: :connection_expired}} -> reconnect()
        {:error, error} -> Logger.error(Exception.message(error))
      end
  """

  alias ZapierSDK.{Action, Catalog, Client, Connection, Error, Result}

  @type connection_ref :: Connection.t() | atom()

  # ── Running actions ──────────────────────────────────────────

  @doc """
  Execute an `Action` against a connection.

  See `ZapierSDK.Client.run/3` for the supported options.
  """
  @spec run(connection_ref(), Action.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def run(conn, %Action{} = action, opts \\ []) do
    Client.run(Connection.resolve!(conn), action, opts)
  end

  @doc "Run a `:search` action."
  @spec search(connection_ref(), String.t(), map(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def search(conn, action, inputs \\ %{}, opts \\ []),
    do: run(conn, Action.search(action, inputs), opts)

  @doc "Run a `:read` action."
  @spec read(connection_ref(), String.t(), map(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def read(conn, action, inputs \\ %{}, opts \\ []),
    do: run(conn, Action.read(action, inputs), opts)

  @doc "Run a `:write` action."
  @spec write(connection_ref(), String.t(), map(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def write(conn, action, inputs \\ %{}, opts \\ []),
    do: run(conn, Action.write(action, inputs), opts)

  # ── Concurrency ──────────────────────────────────────────────

  @doc """
  Run an action in a `Task`.

  Unlike the other helpers the action type is explicit, since a fire-and-forget
  call is just as likely to be a write as a search.

      task = ZapierSDK.async(:drive, :search, "file_v2", %{"title" => "notes"})
      {:ok, result} = Task.await(task, 60_000)
  """
  @spec async(connection_ref(), Action.action_type(), String.t(), map(), keyword()) :: Task.t()
  def async(conn, type, action, inputs \\ %{}, opts \\ []) do
    Client.async(
      Connection.resolve!(conn),
      %Action{name: action, type: type, inputs: inputs},
      opts
    )
  end

  @doc """
  Run many actions concurrently, returning results in the order given.

      results = ZapierSDK.run_many([
        {:drive, Action.search("file_v2", %{"title" => "notes"})},
        {:slack, Action.search("message", %{"query" => "deploy"})}
      ], max_concurrency: 4)
  """
  @spec run_many(
          [{connection_ref(), Action.t()} | {connection_ref(), Action.t(), keyword()}],
          keyword()
        ) :: [{:ok, Result.t()} | {:error, Error.t()}]
  def run_many(entries, opts \\ []) do
    entries
    |> Enum.map(fn
      {conn, action} -> {Connection.resolve!(conn), action}
      {conn, action, entry_opts} -> {Connection.resolve!(conn), action, entry_opts}
    end)
    |> Client.run_many(opts)
  end

  @doc """
  Stream an action's results, fetching pages lazily.

      ZapierSDK.stream(:drive, "file_v2", %{"title" => "report"})
      |> Stream.take(5)
      |> Enum.each(&IO.inspect/1)

  Because a stream has nowhere to return an error tuple, failures raise
  `ZapierSDK.Error`. Use `search/4` when you would rather match on an error.
  """
  @spec stream(connection_ref(), String.t(), map(), keyword()) :: Enumerable.t()
  def stream(conn, action, inputs \\ %{}, opts \\ []) do
    Client.stream(Connection.resolve!(conn), Action.search(action, inputs), opts)
  end

  # ── Discovery ────────────────────────────────────────────────

  @doc """
  List the connections on your account.

  Pass `app: "google-drive"` to filter. This is how you find the UUIDs to put
  in your `:connections` config.
  """
  @spec list_connections(keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  defdelegate list_connections(opts \\ []), to: Catalog

  @doc """
  List the actions an app exposes.

      {:ok, actions} = ZapierSDK.list_actions("google-drive", action_type: "search")
  """
  @spec list_actions(String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  defdelegate list_actions(app, opts \\ []), to: Catalog

  @doc """
  Search the Zapier app catalog.

      {:ok, apps} = ZapierSDK.list_apps(search: "google")
  """
  @spec list_apps(keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  defdelegate list_apps(opts \\ []), to: Catalog

  # ── Connections ──────────────────────────────────────────────

  @doc """
  Build an ad-hoc connection without registering it in config.

      conn = ZapierSDK.connection("google-drive", "02069fbe-9c91-81c1-8567-8ee2dbb7ad64")
  """
  @spec connection(String.t(), String.t(), keyword()) :: Connection.t()
  defdelegate connection(app, id, opts \\ []), to: Connection, as: :new
end
