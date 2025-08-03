defmodule Parrot.ParrotLogger do
  @behaviour :logger_formatter

  def format(level, message, timestamp, metadata) do
    time_str = format_time(timestamp)

    file = Keyword.get(metadata, :file, "nofile")
    line = Keyword.get(metadata, :line, "0")
    function = Keyword.get(metadata, :function, "nofun")

    state = Keyword.get(metadata, :state, nil)
    call_id = Keyword.get(metadata, :call_id, nil)
    transaction_id = Keyword.get(metadata, :transaction_id, nil)
    dialog_id = Keyword.get(metadata, :dialog_id, nil) |> extract_first_dialog_tag()

    parts =
      [
        "[#{file}:#{line}]",
        "[#{function}]",
        state && "[state:#{state}]",
        call_id && "[call_id:#{call_id}]",
        transaction_id && "[transaction_id:#{transaction_id}]",
        dialog_id && "[dialog_id:#{dialog_id}]"
      ]
      # remove nils
      |> Enum.filter(& &1)

    formatted_message = Enum.join(parts, "") <> " " <> to_string(message)

    # Assemble final log line
    "#{time_str} [#{level}] #{formatted_message}\n"
  end

  @impl :logger_formatter
  def format(config, msg) do
    :logger_formatter.format(config, msg)
  end

  # Extract the first tag key from a dialog_id tuple
  defp extract_first_dialog_tag({:dialog_id, {:tag_key, first_tag}, _remote_tag, _callid}) do
    first_tag
  end

  defp extract_first_dialog_tag(_), do: nil

  defp format_time({date, time}) do
    {{year, month, day}, {hour, min, sec, ms}} = {date, time}

    "#{pad2(year)}-#{pad2(month)}-#{pad2(day)} #{pad2(hour)}:#{pad2(min)}:#{pad2(sec)}.#{pad3(ms)}"
  end

  @impl :logger_formatter
  def check_config(_config) do
    :ok
  end

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: "#{n}"

  defp pad3(n) when n < 10, do: "00#{n}"
  defp pad3(n) when n < 100, do: "0#{n}"
  defp pad3(n), do: "#{n}"
end
