defmodule ZapierSDK.Action do
  @moduledoc """
  Represents a Zapier action to be executed.

  An action is identified by its key (`"issues_jql"`) and its type. The type is
  part of the action's identity, not a hint — Zapier exposes separate `search`
  and `write` actions under the same key, and the API rejects a mismatch.
  """

  @enforce_keys [:name, :type]
  defstruct [:name, :type, inputs: %{}, opts: []]

  @type action_type ::
          :read
          | :read_bulk
          | :search
          | :write
          | :filter
          | :run
          | :search_and_write
          | :search_or_write
  @type t :: %__MODULE__{
          name: String.t(),
          type: action_type(),
          inputs: map(),
          opts: keyword()
        }

  @doc "Build a search action."
  @spec search(String.t(), map(), keyword()) :: t()
  def search(name, inputs \\ %{}, opts \\ []) do
    %__MODULE__{name: name, type: :search, inputs: inputs, opts: opts}
  end

  @doc "Build a read action."
  @spec read(String.t(), map(), keyword()) :: t()
  def read(name, inputs \\ %{}, opts \\ []) do
    %__MODULE__{name: name, type: :read, inputs: inputs, opts: opts}
  end

  @doc "Build a write action."
  @spec write(String.t(), map(), keyword()) :: t()
  def write(name, inputs \\ %{}, opts \\ []) do
    %__MODULE__{name: name, type: :write, inputs: inputs, opts: opts}
  end

  @valid_types ~w(read read_bulk search write filter run search_and_write search_or_write)a

  @doc "The action types the Zapier API accepts."
  @spec types() :: [action_type()]
  def types, do: @valid_types

  @doc """
  Render an action type as the API's wire value.

  Raises on an unknown type: catching a typo here beats a confusing 400 from
  the action-run endpoint.
  """
  @spec type_to_api(action_type()) :: String.t()
  def type_to_api(type) when type in @valid_types, do: Atom.to_string(type)

  def type_to_api(type) do
    raise ArgumentError,
          "unknown action type #{inspect(type)}, expected one of: #{inspect(@valid_types)}"
  end
end
