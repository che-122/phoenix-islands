defmodule Dashboard.RSS.RSSContentExtractor do
  @moduledoc false

  @behaviour Saxy.Handler

  @type item :: %{guid: binary() | nil, link: binary() | nil, content: binary() | nil}

  @type state :: %{
          stack: [binary()],
          item_depth: non_neg_integer(),
          capture_field: :guid | :link | :content | nil,
          field_buffer: iolist(),
          current_item: item() | nil,
          items: [item()]
        }

  @spec extract(binary()) :: [item()]
  def extract(xml) when is_binary(xml) do
    case Saxy.parse_string(xml, __MODULE__, initial_state()) do
      {:ok, %{items: items}} -> Enum.reverse(items)
      _ -> []
    end
  end

  @impl true
  def handle_event(:start_document, _prolog, _state), do: {:ok, initial_state()}

  @impl true
  def handle_event(:end_document, _data, state), do: {:ok, state}

  @impl true
  def handle_event(:start_element, {name, _attributes}, state) do
    state = push_stack(state, name)

    state =
      cond do
        name == "item" ->
          state
          |> increment_item_depth()
          |> reset_item_if_starting_top_item()

        state.item_depth > 0 and encoded_tag?(name) ->
          %{state | capture_field: :content, field_buffer: []}

        state.item_depth > 0 and name == "guid" ->
          %{state | capture_field: :guid, field_buffer: []}

        state.item_depth > 0 and name == "link" ->
          %{state | capture_field: :link, field_buffer: []}

        true ->
          state
      end

    {:ok, state}
  end

  @impl true
  def handle_event(:characters, chars, state), do: {:ok, append_field(chars, state)}

  @impl true
  def handle_event(:cdata, chars, state), do: {:ok, append_field(chars, state)}

  @impl true
  def handle_event(:end_element, name, state) do
    state =
      state
      |> maybe_finalize_field(name)
      |> maybe_finalize_item(name)
      |> pop_stack()

    {:ok, state}
  end

  defp initial_state do
    %{
      stack: [],
      item_depth: 0,
      capture_field: nil,
      field_buffer: [],
      current_item: nil,
      items: []
    }
  end

  defp push_stack(state, name), do: %{state | stack: [name | state.stack]}

  defp pop_stack(%{stack: [_head | tail]} = state), do: %{state | stack: tail}
  defp pop_stack(state), do: state

  defp increment_item_depth(state), do: %{state | item_depth: state.item_depth + 1}

  defp reset_item_if_starting_top_item(%{item_depth: 1} = state),
    do: %{state | current_item: %{guid: nil, link: nil, content: nil}}

  defp reset_item_if_starting_top_item(state), do: state

  defp append_field(chars, %{capture_field: field} = state)
       when is_binary(chars) and field in [:guid, :link, :content] do
    %{state | field_buffer: [chars | state.field_buffer]}
  end

  defp append_field(_chars, state), do: state

  defp maybe_finalize_field(%{capture_field: nil} = state, _name), do: state

  defp maybe_finalize_field(%{capture_field: field} = state, name) when is_binary(name) do
    if field_closed_by_tag?(field, name) do
      value =
        state.field_buffer
        |> Enum.reverse()
        |> IO.iodata_to_binary()
        |> String.trim()

      state = %{state | capture_field: nil, field_buffer: []}

      if value == "" do
        state
      else
        put_item_field(state, field, value)
      end
    else
      state
    end
  end

  defp field_closed_by_tag?(:guid, "guid"), do: true
  defp field_closed_by_tag?(:link, "link"), do: true
  defp field_closed_by_tag?(:content, name), do: encoded_tag?(name)
  defp field_closed_by_tag?(_, _), do: false

  defp put_item_field(%{current_item: item} = state, field, value) when is_map(item) do
    %{state | current_item: Map.put(item, field, value)}
  end

  defp put_item_field(state, _field, _value), do: state

  defp maybe_finalize_item(%{item_depth: depth} = state, "item") when depth > 0 do
    depth = depth - 1
    state = %{state | item_depth: depth}

    if depth == 0 do
      %{state | items: [state.current_item | state.items], current_item: nil}
    else
      state
    end
  end

  defp maybe_finalize_item(state, _name), do: state

  defp encoded_tag?(name) when is_binary(name), do: local_name(name) == "encoded"

  defp local_name(name) do
    case String.split(name, ":", parts: 2) do
      [_prefix, local] -> local
      [local] -> local
    end
  end
end
