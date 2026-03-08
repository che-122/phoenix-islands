defmodule DashboardWeb.PageController do
  use DashboardWeb, :controller

  alias Dashboard.RSS

  def home(conn, _params) do
    render(conn, :home)
  end

  def list(conn, _params) do
    feeds = RSS.list_feed()
    render(conn, :list, feeds: feeds)
  end

  def entries(conn, %{"feed_id" => feed_id}) do
    feed = RSS.get_feed!(feed_id)
    entries = RSS.list_feed_entries(feed_id)

    render(conn, :entries, feed: feed, entries: entries)
  end

  def entry(conn, %{"feed_id" => feed_id, "entry_id" => entry_id}) do
    feed = RSS.get_feed!(feed_id)
    entry = RSS.get_feed_entry!(feed_id, entry_id)

    render(conn, :entry, feed: feed, entry: entry)
  end
end
