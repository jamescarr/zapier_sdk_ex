defmodule ZapierSDK.Client do
  @moduledoc """
  Execution engine: turns a connection and an action into an HTTP action run.

  Running an action against Zapier is a two-phase protocol rather than a single
  call. We `POST` a run and get an ID back, then poll that ID until the run
  leaves the `"waiting"` state. This module hides both phases, plus cursor
  pagination, behind `run/3`.

  It holds no process state — each call runs in the caller's own process, so
  concurrency is just a matter of starting more callers.
  """

  alias ZapierSDK.{Action, Catalog, Connection, Error, HTTP, Result, Telemetry}

  @runs_path "/api/v0/sdk/zapier/api/actions/v1/runs"

  # Poll gently at first so quick actions return fast, then back off so slow
  # ones don't hammer the API for the full timeout window.
  @initial_poll_ms 250
  @max_poll_ms 2_000

  @doc """
  Execute an action and return every page of results.

  ## Options

    * `:timeout` — milliseconds to wait for the run, defaults to
      `ZapierSDK.Config.action_timeout/0` (180s)
    * `:max_items` — stop after this many items rather than draining all pages
    * `:page_size` — items requested per page
  """
  @spec run(Connection.t(), Action.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(%Connection{} = conn, %Action{} = action, opts \\ []) do
    meta = %{connection: conn, action: action}

    Telemetry.span([:zapier_sdk, :action], meta, fn ->
      started = System.monotonic_time(:millisecond)

      case collect_pages(conn, action, opts) do
        {:ok, items} ->
          {:ok,
           Result.new(items,
             elapsed_ms: System.monotonic_time(:millisecond) - started,
             action_name: action.name,
             connection_app: conn.app
           )}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end)
  end

  @doc "Execute an action in a `Task`."
  @spec async(Connection.t(), Action.t(), keyword()) :: Task.t()
  def async(%Connection{} = conn, %Action{} = action, opts \\ []) do
    Task.async(fn -> run(conn, action, opts) end)
  end

  @doc """
  Execute many actions concurrently, preserving input order.

  Each element is `{connection, action}` or `{connection, action, opts}`.
  """
  @spec run_many([tuple()], keyword()) :: [{:ok, Result.t()} | {:error, Error.t()}]
  def run_many(entries, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(opts, :timeout, ZapierSDK.Config.action_timeout())

    entries
    |> Task.async_stream(
      fn
        {conn, action} -> run(conn, action, opts)
        {conn, action, entry_opts} -> run(conn, action, Keyword.merge(opts, entry_opts))
      end,
      max_concurrency: max_concurrency,
      # Give the surrounding stream a moment beyond the per-action timeout so a
      # slow action reports its own :timeout error instead of being killed here.
      timeout: timeout + 5_000,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, Error.timeout(timeout)}
      {:exit, reason} -> {:error, Error.new(:transport_error, "action crashed", details: reason)}
    end)
  end

  @doc """
  Stream results page by page.

  Pages are fetched lazily, so `Stream.take/2` stops early instead of draining
  every page the action can produce.
  """
  @spec stream(Connection.t(), Action.t(), keyword()) :: Enumerable.t()
  def stream(%Connection{} = conn, %Action{} = action, opts \\ []) do
    Stream.resource(
      fn -> {:start, nil} end,
      fn
        :done ->
          {:halt, :done}

        {:start, _} ->
          emit_page(conn, action, nil, opts)

        {:cont, cursor} ->
          emit_page(conn, action, cursor, opts)
      end,
      fn _ -> :ok end
    )
  end

  defp emit_page(conn, action, cursor, opts) do
    case execute_page(conn, action, cursor, opts) do
      {:ok, items, nil} -> {items, :done}
      {:ok, items, next} -> {items, {:cont, next}}
      # Streams have nowhere to put an error tuple, so surface it as a raise
      # rather than silently truncating the results.
      {:error, error} -> raise error
    end
  end

  defp collect_pages(conn, action, opts) do
    max_items = Keyword.get(opts, :max_items)
    do_collect(conn, action, nil, opts, [], max_items)
  end

  defp do_collect(conn, action, cursor, opts, acc, max_items) do
    case execute_page(conn, action, cursor, opts) do
      {:error, error} ->
        {:error, error}

      {:ok, items, next_cursor} ->
        acc = acc ++ items

        cond do
          max_items && length(acc) >= max_items -> {:ok, Enum.take(acc, max_items)}
          is_nil(next_cursor) -> {:ok, acc}
          true -> do_collect(conn, action, next_cursor, opts, acc, max_items)
        end
    end
  end

  defp execute_page(conn, action, cursor, opts) do
    timeout = Keyword.get(opts, :timeout, ZapierSDK.Config.action_timeout())

    with {:ok, run_id} <- create_run(conn, action, cursor, opts),
         {:ok, payload} <- poll(run_id, timeout) do
      {:ok, payload["results"] || [], next_cursor(payload)}
    end
  end

  defp create_run(conn, action, cursor, opts) do
    with {:ok, implementation_id} <- Catalog.implementation_id(conn.app),
         {:ok, action_id} <- Catalog.action_id(conn.app, action.name, action.type) do
      body =
        %{
          "selected_api" => implementation_id,
          "action_id" => action_id,
          "action_key" => action.name,
          "action_type" => Action.type_to_api(action.type),
          "inputs" => stringify_inputs(action.inputs),
          "authentication_id" => conn.id
        }
        |> maybe_put("page", cursor)
        |> maybe_put("page_size", opts[:page_size])

      case HTTP.request(:post, @runs_path, json: %{"data" => body}) do
        {:ok, %{"id" => id}, _resp} ->
          {:ok, id}

        {:ok, other, _resp} ->
          {:error, Error.new(:invalid_response, "action run response had no id", details: other)}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp poll(run_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_poll(run_id, deadline, timeout, @initial_poll_ms)
  end

  defp do_poll(run_id, deadline, timeout, backoff) do
    case HTTP.request(:get, "#{@runs_path}/#{URI.encode(run_id)}") do
      {:error, error} ->
        {:error, error}

      {:ok, payload, _resp} ->
        cond do
          not pending?(payload) ->
            finish(payload)

          System.monotonic_time(:millisecond) >= deadline ->
            {:error, Error.timeout(timeout, %{run_id: run_id})}

          true ->
            Process.sleep(backoff)
            do_poll(run_id, deadline, timeout, min(backoff * 2, @max_poll_ms))
        end
    end
  end

  defp pending?(%{"status" => "waiting"}), do: true
  defp pending?(_), do: false

  # A finished run can still carry integration-level failures. Reporting these
  # as errors is the whole point: an expired connection must not look like a
  # successful search that happened to return nothing.
  defp finish(%{"errors" => errors}) when is_list(errors) and errors != [] do
    {:error, Error.from_action_errors(errors)}
  end

  defp finish(payload), do: {:ok, payload}

  defp next_cursor(%{"next_page" => page}) when not is_nil(page), do: to_string(page)
  defp next_cursor(_), do: nil

  # Zapier's action inputs are a JSON object; atom keys are a convenience we
  # normalise here so callers can use either.
  defp stringify_inputs(inputs) when is_map(inputs) do
    Map.new(inputs, fn {k, v} -> {to_string(k), v} end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
