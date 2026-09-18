defmodule ZapierSDK.Result do
  @moduledoc """
  Parsed result from a Zapier SDK action execution.

  Results wrap the raw data returned by the CLI with metadata about
  the execution — timing, count, and the raw output for debugging.
  """

  defstruct [
    :data,
    :count,
    :elapsed_ms,
    :action_name,
    :connection_app,
    raw_output: nil
  ]

  @type t :: %__MODULE__{
          data: [map()],
          count: non_neg_integer(),
          elapsed_ms: non_neg_integer(),
          action_name: String.t() | nil,
          connection_app: String.t() | nil,
          raw_output: String.t() | nil
        }

  @doc "Create a result from parsed data and execution metadata."
  @spec new([map()], keyword()) :: t()
  def new(data, meta \\ []) when is_list(data) do
    %__MODULE__{
      data: data,
      count: length(data),
      elapsed_ms: Keyword.get(meta, :elapsed_ms, 0),
      action_name: Keyword.get(meta, :action_name),
      connection_app: Keyword.get(meta, :connection_app),
      raw_output: Keyword.get(meta, :raw_output)
    }
  end

  @doc "Get the first result or nil."
  @spec first(t()) :: map() | nil
  def first(%__MODULE__{data: [head | _]}), do: head
  def first(%__MODULE__{data: []}), do: nil

  @doc "Returns true if the result has no data."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{data: []}), do: true
  def empty?(%__MODULE__{}), do: false

  defimpl Enumerable do
    def count(%ZapierSDK.Result{count: count}), do: {:ok, count}
    def member?(%ZapierSDK.Result{data: data}, element), do: {:ok, element in data}
    def slice(_result), do: {:error, __MODULE__}

    def reduce(%ZapierSDK.Result{data: data}, acc, fun) do
      Enumerable.List.reduce(data, acc, fun)
    end
  end
end
