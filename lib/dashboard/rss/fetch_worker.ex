defmodule Dashboard.RSS.FetchWorker do
  @moduledoc """
  Responsible for fetching feed sources via HTTP with proper revalidation.

  Uses conditional requests (ETag, Last-Modified) and returns rich result
  tuples that the IngestService can use for scheduling decisions.

  ## Return types

  - `{:ok, feed, response}` — 200 OK, content available for processing
  - `{:not_modified, feed, response}` — 304 Not Modified
  - `{:redirect, feed, new_url, response}` — 301/308 permanent redirect
  - `{:rate_limited, feed, response}` — 429 Too Many Requests
  - `{:server_error, feed, status, response}` — 5xx server errors
  - `{:gone, feed, response}` — 410 Gone
  - `{:not_found, feed, response}` — 404 Not Found
  - `{:error, feed, reason}` — network/TLS/DNS failure
  """

  alias Dashboard.RSS.Feed
  alias Dashboard.HttpUtils

  @user_agent "Dashboard/1.0 (RSS feed bot)"

  def fetch_feed(%Feed{} = feed) do
    url = feed.canonical_url || feed.url

    headers =
      [
        {"User-Agent", @user_agent},
        {"Accept-Encoding", "gzip, deflate"}
      ]
      |> safe_add_header("If-Modified-Since", feed.last_modified)
      |> safe_add_header("If-None-Match", feed.etag)

    case Req.get(url, headers: headers, redirect: false) do
      {:ok, %Req.Response{} = response} -> classify_response(feed, response)
      {:error, %Req.TransportError{reason: reason}} -> {:error, feed, reason}
      {:error, reason} -> {:error, feed, reason}
    end
  end

  defp classify_response(feed, %Req.Response{status: 200} = response) do
    case check_is_modified(feed, response) do
      :modified -> {:ok, feed, response}
      :not_modified -> {:not_modified, feed, response}
    end
  end

  defp classify_response(feed, %Req.Response{status: status} = response)
       when status in [301, 308] do
    new_url = HttpUtils.extract_header("location", response)

    if new_url do
      {:redirect, feed, new_url, response}
    else
      {:error, feed, :redirect_without_location}
    end
  end

  defp classify_response(feed, %Req.Response{status: status} = response)
       when status in [302, 307] do
    new_url = HttpUtils.extract_header("location", response)

    if new_url do
      temp_feed = %{feed | canonical_url: new_url}
      fetch_feed(temp_feed)
    else
      {:error, feed, :redirect_without_location}
    end
  end

  defp classify_response(feed, %Req.Response{status: 304} = response) do
    {:not_modified, feed, response}
  end

  defp classify_response(feed, %Req.Response{status: 429} = response) do
    {:rate_limited, feed, response}
  end

  defp classify_response(feed, %Req.Response{status: 410} = response) do
    {:gone, feed, response}
  end

  defp classify_response(feed, %Req.Response{status: 404} = response) do
    {:not_found, feed, response}
  end

  defp classify_response(feed, %Req.Response{status: status} = response) when status >= 500 do
    {:server_error, feed, status, response}
  end

  defp classify_response(feed, %Req.Response{status: status} = _response) do
    {:error, feed, {:unexpected_status, status}}
  end

  defp check_is_modified(feed, response) do
    response_etag = HttpUtils.extract_header("etag", response)
    response_last_modified = HttpUtils.extract_header("last-modified", response)

    cond do
      HttpUtils.matching_headers?(response_etag, feed.etag) -> :not_modified
      HttpUtils.matching_headers?(response_last_modified, feed.last_modified) -> :not_modified
      true -> :modified
    end
  end

  defp safe_add_header(headers, _name, nil), do: headers
  defp safe_add_header(headers, name, value), do: [{name, value} | headers]
end
