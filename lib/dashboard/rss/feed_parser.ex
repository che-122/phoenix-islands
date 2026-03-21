defmodule Dashboard.RSS.FeedParser do
  @moduledoc false

  alias Dashboard.RSS.RSSContentExtractor

  @spec parse_string(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse_string(xml, opts \\ []) when is_binary(xml) and is_list(opts) do
    with {:ok, parsed} <- Gluttony.parse_string(xml, opts) do
      {:ok, maybe_enrich_rss_entries(parsed, xml)}
    end
  end

  defp maybe_enrich_rss_entries(%{type: :rss2, entries: entries} = parsed, xml)
       when is_list(entries) do
    extracted_items = RSSContentExtractor.extract(xml)
    entries = merge_content(entries, extracted_items)
    %{parsed | entries: entries}
  end

  defp maybe_enrich_rss_entries(parsed, _xml), do: parsed

  defp merge_content(entries, extracted_items) do
    {entries, _remaining} =
      Enum.map_reduce(entries, extracted_items, fn entry, remaining_items ->
        {content, remaining_items} = pick_content_for_entry(entry, remaining_items)

        merged_entry =
          if is_binary(content) and String.trim(content) != "" do
            Map.put(entry, :content, content)
          else
            entry
          end

        {merged_entry, remaining_items}
      end)

    entries
  end

  defp pick_content_for_entry(entry, items) do
    guid = Map.get(entry, :guid)
    link = Map.get(entry, :link) || Map.get(entry, :url)

    with {:error, :not_found} <- find_and_pop_by(items, &match_guid?(&1, guid)),
         {:error, :not_found} <- find_and_pop_by(items, &match_link?(&1, link)) do
      {nil, items}
    else
      {:ok, item, rest} -> {Map.get(item, :content), rest}
    end
  end

  defp find_and_pop_by(items, matcher) when is_list(items) and is_function(matcher, 1) do
    index = Enum.find_index(items, matcher)

    if is_integer(index) do
      {left, [item | right]} = Enum.split(items, index)
      {:ok, item, left ++ right}
    else
      {:error, :not_found}
    end
  end

  defp match_guid?(item, guid) when is_binary(guid) and guid != "", do: item.guid == guid
  defp match_guid?(_item, _guid), do: false

  defp match_link?(item, link) when is_binary(link) and link != "", do: item.link == link
  defp match_link?(_item, _link), do: false
end
