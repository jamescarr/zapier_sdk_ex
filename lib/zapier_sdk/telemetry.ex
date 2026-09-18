defmodule ZapierSDK.Telemetry do
  @moduledoc """
  Telemetry events emitted by the Zapier SDK client.

  All events are prefixed with `[:zapier_sdk]`.

  ## Events

  ### `[:zapier_sdk, :action, :start]`
  Emitted when an action begins execution.

  Measurements: `%{system_time: integer()}`
  Metadata: `%{connection: Connection.t(), action: Action.t()}`

  ### `[:zapier_sdk, :action, :stop]`
  Emitted when an action completes successfully.

  Measurements: `%{duration: integer()}` (native time units)
  Metadata: `%{connection: Connection.t(), action: Action.t(), result: Result.t()}`

  ### `[:zapier_sdk, :action, :exception]`
  Emitted when an action raises or exits.

  Measurements: `%{duration: integer()}`
  Metadata: `%{connection: Connection.t(), action: Action.t(), kind: atom(), reason: term(), stacktrace: list()}`

  Note that a returned `{:error, %ZapierSDK.Error{}}` is *not* an exception: it
  arrives as a `:stop` event whose `:result` is the error tuple. Handlers that
  count failures should match on the result rather than only on `:exception`.

  ## Attaching Handlers

      :telemetry.attach("my-handler", [:zapier_sdk, :action, :stop], &MyModule.handle/4, nil)
  """

  @doc false
  def span(event_prefix, meta, fun) do
    :telemetry.span(event_prefix, meta, fn ->
      result = fun.()
      {result, meta}
    end)
  end

  @doc false
  def event(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end
end
