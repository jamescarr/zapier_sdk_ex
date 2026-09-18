defmodule ZapierSDK.Catalog do
  @moduledoc """
  Looks up the app, action, and connection metadata the SDK API needs.

  Starting an action run requires two identifiers that callers shouldn't have
  to know about: the app's versioned `implementation_id` (`SlackCLIAPI@1.43.0`)
  and the action's internal `id` (`core:3516535`). This module resolves both
  from the friendly names you pass to `ZapierSDK.run/3`.

  Those identifiers change only when an app publishes a new version, so results
  are cached in ETS with a TTL. Without the cache every action would cost three
  HTTP round trips instead of two.
  """

  use GenServer

  alias ZapierSDK.{Error, HTTP}

  @table __MODULE__
  @ttl_ms :timer.minutes(30)

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Resolve an app's versioned implementation ID.

  Accepts a slug (`"google-drive"`), an app key (`"GoogleDriveCLIAPI"`), or an
  already-versioned implementation ID, which is returned untouched.
  """
  @spec implementation_id(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def implementation_id(app) do
    if String.contains?(app, "@") do
      {:ok, app}
    else
      cached({:app, app}, fn -> fetch_implementation_id(app) end)
    end
  end

  @doc "Resolve an action's internal ID, validating that its type matches."
  @spec action_id(String.t(), String.t(), atom()) :: {:ok, String.t()} | {:error, Error.t()}
  def action_id(app, action_key, action_type) do
    cached({:action, app, action_key, action_type}, fn ->
      fetch_action_id(app, action_key, action_type)
    end)
  end

  @doc """
  List connections, optionally filtered by app.

  Useful for discovering the connection UUIDs to put in your config.
  """
  @spec list_connections(keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_connections(opts \\ []) do
    params =
      [owner: Keyword.get(opts, :owner, "me"), page_size: Keyword.get(opts, :page_size, 100)]
      |> maybe_put(:app_key, opts[:app])

    case HTTP.request(:get, "/api/v0/connections", params: params) do
      {:ok, data, _resp} when is_list(data) -> {:ok, data}
      {:ok, _other, _resp} -> {:ok, []}
      {:error, error} -> {:error, error}
    end
  end

  @doc "List the actions an app exposes, optionally filtered by type."
  @spec list_actions(String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_actions(app, opts \\ []) do
    params = maybe_put([app_key: app], :action_type, opts[:action_type])

    case HTTP.request(:get, "/api/v0/actions", params: params) do
      {:ok, data, _resp} when is_list(data) -> {:ok, data}
      {:ok, _other, _resp} -> {:ok, []}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Search the Zapier app catalog."
  @spec list_apps(keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_apps(opts \\ []) do
    params =
      [page_size: Keyword.get(opts, :page_size, 50)]
      |> maybe_put(:search, opts[:search])
      |> maybe_put(:app_keys, opts[:app_keys])

    case HTTP.request(:get, "/api/v0/apps", params: params) do
      {:ok, data, _resp} when is_list(data) -> {:ok, data}
      {:ok, _other, _resp} -> {:ok, []}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Drop all cached metadata. Mainly useful in tests."
  @spec flush() :: :ok
  def flush do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  defp fetch_implementation_id(app) do
    with {:ok, apps} <- list_apps(app_keys: app) do
      match =
        Enum.find(apps, fn a ->
          a["slug"] == app or a["key"] == app or a["implementation_id"] == app
        end) || List.first(apps)

      case match do
        %{"implementation_id" => id} when is_binary(id) ->
          {:ok, id}

        _ ->
          {:error,
           Error.new(:app_not_found, "no Zapier app matched #{inspect(app)}", details: apps)}
      end
    end
  end

  defp fetch_action_id(app, action_key, action_type) do
    type = to_string(action_type)

    with {:ok, actions} <- list_actions(app, action_type: type) do
      case Enum.find(actions, &(&1["key"] == action_key)) do
        %{"id" => id} ->
          {:ok, id}

        nil ->
          {:error,
           Error.new(
             :action_not_found,
             "#{app} has no #{type} action named #{inspect(action_key)}",
             details: available(actions)
           )}
      end
    end
  end

  # Surfacing the visible action keys turns "action_not_found" from a dead end
  # into something the caller can usually fix without leaving the error.
  defp available(actions) do
    actions
    |> Enum.reject(& &1["is_hidden"])
    |> Enum.map(& &1["key"])
    |> Enum.sort()
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Keyword.put(params, key, value)

  defp cached(key, fun) do
    ensure_table()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        {:ok, value}

      _ ->
        with {:ok, value} <- fun.() do
          :ets.insert(@table, {key, value, now + @ttl_ms})
          {:ok, value}
        end
    end
  end

  # The table is normally created by the supervised process, but falling back
  # to creating it on demand keeps the SDK usable in scripts and tests that
  # never start the application.
  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end
  catch
    :error, :badarg -> :ok
  end

  @impl true
  def init(_opts) do
    ensure_table()
    {:ok, %{}}
  end
end
