defmodule ZapierSDK.Apps.GoogleCalendar do
  @moduledoc """
  Convenience wrappers for Google Calendar actions.

  Expects a `:calendar` connection, or pass `connection:` to override:

      config :zapier_sdk, connections: [
        calendar: {"google-calendar", "your-connection-uuid"}
      ]

  ## Examples

      {:ok, result} = ZapierSDK.Apps.GoogleCalendar.today_events()
      {:ok, result} = ZapierSDK.Apps.GoogleCalendar.find_events(search_term: "standup")
  """

  alias ZapierSDK.{Action, Error, Result}

  @default_conn :calendar

  @doc """
  Find events, optionally bounded by time.

  ## Options

    * `:calendar_id` — defaults to `"primary"`
    * `:start_time` / `:end_time` — ISO 8601 strings
    * `:search_term` — free-text match
    * `:expand_recurring` — expand recurring events into instances
  """
  @spec find_events(keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def find_events(opts \\ []) do
    inputs =
      %{"calendarid" => Keyword.get(opts, :calendar_id, "primary")}
      |> maybe_put("start_time", opts[:start_time])
      |> maybe_put("end_time", opts[:end_time])
      |> maybe_put("search_term", opts[:search_term])
      |> maybe_put("expand_recurring", opts[:expand_recurring])
      |> maybe_put("ordering", opts[:ordering])

    run(Action.search("event_v2", inputs), opts)
  end

  @doc "Events occurring today (UTC)."
  @spec today_events(keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def today_events(opts \\ []) do
    today = Date.utc_today()

    find_events(
      Keyword.merge(opts,
        start_time: iso_at(today, ~T[00:00:00]),
        end_time: iso_at(Date.add(today, 1), ~T[00:00:00])
      )
    )
  end

  @doc "Events in the next `days` days, seven by default."
  @spec upcoming_events(keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def upcoming_events(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    now = DateTime.utc_now()

    find_events(
      Keyword.merge(opts,
        start_time: DateTime.to_iso8601(now),
        end_time: now |> DateTime.add(days, :day) |> DateTime.to_iso8601()
      )
    )
  end

  @doc "Find busy periods between two ISO 8601 timestamps."
  @spec busy_periods(String.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def busy_periods(start_time, end_time, opts \\ []) do
    inputs = %{
      "calendarid" => Keyword.get(opts, :calendar_id, "primary"),
      "start_time" => start_time,
      "end_time" => end_time
    }

    run(Action.search("find_busy_periods", inputs), opts)
  end

  @doc ~S"""
  Create an event from natural language, e.g. `"Lunch with Sam tomorrow at 1pm"`.
  """
  @spec quick_add(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def quick_add(text, opts \\ []) do
    inputs =
      %{"calendarid" => Keyword.get(opts, :calendar_id, "primary"), "text" => text}
      |> maybe_put("attendees", opts[:attendees])

    run(Action.write("event", inputs), opts)
  end

  defp iso_at(date, time) do
    date |> DateTime.new!(time, "Etc/UTC") |> DateTime.to_iso8601()
  end

  defp run(action, opts) do
    ZapierSDK.run(Keyword.get(opts, :connection, @default_conn), action, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
