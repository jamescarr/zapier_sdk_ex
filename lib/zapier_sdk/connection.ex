defmodule ZapierSDK.Connection do
  @moduledoc """
  An authenticated link between your Zapier account and a third-party app.

  A connection pairs an app (`"google-drive"`) with a connection ID from your
  account. Every action runs in the context of one, so the connection is the
  credential boundary.

  ## Finding your connection IDs

  Connection IDs are UUIDs. List them with `ZapierSDK.list_connections/1`:

      {:ok, connections} = ZapierSDK.list_connections()
      Enum.each(connections, &IO.puts("\#{&1["id"]}  \#{&1["title"]}"))

  ## Named connections

  Register the ones you use regularly and refer to them by atom:

      config :zapier_sdk, connections: [
        drive: {"google-drive", "02069fbe-9c91-81c1-8567-8ee2dbb7ad64"},
        slack: {"slack", "02217725-24ba-8453-b2c2-75f41bf95747"}
      ]

      ZapierSDK.search(:drive, "file_v2", %{"title" => "budget"})

  ## Ad-hoc connections

      conn = ZapierSDK.connection("google-drive", "02069fbe-9c91-81c1-8567-8ee2dbb7ad64")
      ZapierSDK.search(conn, "file_v2", %{"title" => "budget"})
  """

  alias ZapierSDK.Config

  @enforce_keys [:app, :id]
  defstruct [:app, :id, :label, metadata: %{}]

  @type t :: %__MODULE__{
          app: String.t(),
          id: String.t(),
          label: String.t() | nil,
          metadata: map()
        }

  @doc "Build a connection from an app key or slug and a connection ID."
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(app, id, opts \\ []) do
    %__MODULE__{
      app: app,
      id: to_string(id),
      label: Keyword.get(opts, :label),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Resolve a connection struct, or look up a named one from config.

  Raises `ArgumentError` for an unknown name — a missing connection is a
  configuration mistake, and failing loudly at the call site is friendlier
  than a 404 from the API later.
  """
  @spec resolve!(t() | atom()) :: t()
  def resolve!(%__MODULE__{} = conn), do: conn

  def resolve!(name) when is_atom(name) do
    connections = Config.connections()

    case Keyword.get(connections, name) do
      {app, id} ->
        new(app, id, label: to_string(name))

      {app, id, opts} ->
        new(app, id, Keyword.merge([label: to_string(name)], opts))

      nil ->
        raise ArgumentError,
              "no connection named #{inspect(name)} configured. " <>
                "Known connections: #{inspect(Keyword.keys(connections))}. " <>
                "Add one under `config :zapier_sdk, connections: [...]`, or run " <>
                "ZapierSDK.list_connections/1 to find its ID."
    end
  end
end
