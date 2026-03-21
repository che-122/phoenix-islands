defmodule Dashboard.RSS.IngestServiceRealParserTest do
  use Dashboard.DataCase

  alias Dashboard.RSS
  alias Dashboard.RSS.Feed
  alias Dashboard.RSS.IngestService

  setup do
    previous_fetch_worker = Application.get_env(:dashboard, :rss_fetch_worker)
    previous_feed_parser = Application.get_env(:dashboard, :rss_feed_parser)

    Application.put_env(:dashboard, :rss_fetch_worker, __MODULE__.FakeFetchWorker)
    Application.put_env(:dashboard, :rss_feed_parser, Dashboard.RSS.FeedParser)

    on_exit(fn ->
      restore_env(:rss_fetch_worker, previous_fetch_worker)
      restore_env(:rss_feed_parser, previous_feed_parser)
    end)

    :ok
  end

  test "update_pipeline/1 persists rss content:encoded into feed entry content" do
    feed = create_feed!("test://rss-content-encoded")

    assert {:ok, %Feed{} = updated_feed} = IngestService.update_pipeline(feed)

    entries = RSS.list_feed_entries(updated_feed.id)
    assert length(entries) == 2

    first = Enum.find(entries, &(&1.guid == "guid-1"))
    second = Enum.find(entries, &(&1.guid == "guid-2"))

    assert first.content == "<p>Full HTML body</p>"
    assert first.summary == "Short summary"
    assert second.content == nil
    assert second.summary == "Only summary"
  end

  defp create_feed!(url) do
    {:ok, feed} =
      RSS.create_feed(%{
        title: "Seed Feed",
        url: url,
        status: :active,
        miss_count: 0,
        error_count: 0
      })

    feed
  end

  defp restore_env(key, nil), do: Application.delete_env(:dashboard, key)
  defp restore_env(key, value), do: Application.put_env(:dashboard, key, value)

  defmodule FakeFetchWorker do
    alias Dashboard.RSS.Feed

    def fetch_feed(%Feed{url: "test://rss-content-encoded"} = feed) do
      xml = """
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <title>Parser Test Feed</title>
          <link>https://example.com/feed</link>
          <description>Feed Description</description>
          <item>
            <title>Entry One</title>
            <guid>guid-1</guid>
            <link>https://example.com/posts/1</link>
            <pubDate>Tue, 03 Mar 2026 10:00:00 GMT</pubDate>
            <description>Short summary</description>
            <content:encoded><![CDATA[<p>Full HTML body</p>]]></content:encoded>
          </item>
          <item>
            <title>Entry Two</title>
            <guid>guid-2</guid>
            <link>https://example.com/posts/2</link>
            <pubDate>Mon, 02 Mar 2026 10:00:00 GMT</pubDate>
            <description>Only summary</description>
          </item>
        </channel>
      </rss>
      """

      response = %Req.Response{status: 200, headers: [], body: xml}
      {:ok, feed, response}
    end
  end
end
