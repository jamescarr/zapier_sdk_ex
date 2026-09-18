defmodule ZapierSDK.ZapierStub do
  @moduledoc """
  A stand-in for the Zapier SDK API, used by the test suite.

  Rather than stubbing one request at a time, this plug implements the real
  protocol: metadata lookups, `POST /runs`, and polling `GET /runs/:id`. Tests
  describe the *outcome* they want for an action and let the stub replay the
  same call sequence the SDK performs in production, so a change in that
  sequence is caught here instead of in production.
  """

  import Plug.Conn

  @doc """
  Install the stub.

  ## Options

    * `:pages` — list of pages, each `{results, next_page}`; defaults to one
      empty page
    * `:errors` — action errors to return on the final poll
    * `:waits` — how many `"waiting"` polls to emit before finishing
    * `:actions` — action metadata returned by `/api/v0/actions`
    * `:apps` — app metadata returned by `/api/v0/apps`
    * `:connections` — connections returned by `/api/v0/connections`
  """
  def install(opts \\ []) do
    state = :counters.new(2, [])

    Req.Test.stub(ZapierSDK, fn conn ->
      dispatch(conn, opts, state)
    end)
  end

  defp dispatch(%{request_path: "/api/v0/apps"} = conn, opts, _state) do
    apps =
      Keyword.get(opts, :apps, [
        %{
          "slug" => "google-drive",
          "key" => "GoogleDriveCLIAPI",
          "implementation_id" => "GoogleDriveCLIAPI@3.1.0"
        }
      ])

    envelope(conn, apps)
  end

  defp dispatch(%{request_path: "/api/v0/actions"} = conn, opts, _state) do
    actions =
      Keyword.get(opts, :actions, [
        %{"id" => "core:1", "key" => "file_v2", "action_type" => "search"}
      ])

    envelope(conn, actions)
  end

  defp dispatch(%{request_path: "/api/v0/connections"} = conn, opts, _state) do
    envelope(conn, Keyword.get(opts, :connections, []))
  end

  defp dispatch(%{method: "POST", request_path: path} = conn, _opts, state) do
    true = String.ends_with?(path, "/actions/v1/runs")
    # Counter 1 tracks which page we're on; counter 2 tracks polls within it.
    :counters.add(state, 1, 1)
    :counters.put(state, 2, 0)

    envelope(conn, %{
      "id" => "run-#{:counters.get(state, 1)}",
      "implementation_id" => "GoogleDriveCLIAPI@3.1.0"
    })
  end

  defp dispatch(%{method: "GET", request_path: path} = conn, opts, state) do
    true = String.contains?(path, "/actions/v1/runs/")
    waits = Keyword.get(opts, :waits, 0)
    polls = :counters.get(state, 2)
    :counters.add(state, 2, 1)

    if polls < waits do
      envelope(conn, %{"id" => "run", "status" => "waiting"}, 202)
    else
      finished(conn, opts, :counters.get(state, 1))
    end
  end

  defp finished(conn, opts, page_number) do
    case Keyword.get(opts, :errors, []) do
      [] ->
        pages = Keyword.get(opts, :pages, [{[], nil}])
        {results, next_page} = Enum.at(pages, page_number - 1, {[], nil})

        body =
          %{"id" => "run", "status" => "success", "results" => results, "errors" => []}
          |> put_next_page(next_page)

        envelope(conn, body)

      errors ->
        envelope(conn, %{
          "id" => "run",
          "status" => "error",
          "results" => [],
          "errors" => errors
        })
    end
  end

  defp put_next_page(body, nil), do: body
  defp put_next_page(body, page), do: Map.put(body, "next_page", page)

  defp envelope(conn, data, status \\ 200) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{"data" => data, "errors" => []}))
  end
end
