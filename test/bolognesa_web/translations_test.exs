defmodule BolognesaWeb.TranslationsTest do
  use ExUnit.Case, async: true

  alias Expo.Message
  alias Expo.Message.Plural
  alias Expo.Message.Singular

  test "both languages cover every extracted message, plural and interpolation" do
    for domain <- ["default", "errors"], locale <- ["es", "en"] do
      template = Expo.PO.parse_file!("priv/gettext/#{domain}.pot")
      catalog = Expo.PO.parse_file!("priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po")
      messages = Enum.reject(catalog.messages, & &1.obsolete)
      assert MapSet.new(messages, &key/1) == MapSet.new(template.messages, &key/1)

      for message <- messages do
        refute Message.has_flag?(message, "fuzzy")

        for {source, translation} <- translations(message) do
          refute IO.iodata_to_binary(translation) == ""
          assert placeholders(source) == placeholders(translation)
        end
      end
    end
  end

  test "count translations preserve singular and plural" do
    Gettext.with_locale(BolognesaWeb.Gettext, "en", fn ->
      assert Gettext.gettext(BolognesaWeb.Gettext, "Guardar") == "Save"

      assert Gettext.ngettext(BolognesaWeb.Gettext, "%{count} versión", "%{count} versiones", 1) ==
               "1 version"

      assert Gettext.ngettext(BolognesaWeb.Gettext, "%{count} versión", "%{count} versiones", 2) ==
               "2 versions"
    end)
  end

  defp key(%Singular{} = message), do: Singular.key(message)
  defp key(%Plural{} = message), do: Plural.key(message)
  defp translations(%Singular{} = message), do: [{message.msgid, message.msgstr}]

  defp translations(%Plural{} = message) do
    assert Map.keys(message.msgstr) |> Enum.sort() == [0, 1]
    [{message.msgid, message.msgstr[0]}, {message.msgid_plural, message.msgstr[1]}]
  end

  defp placeholders(text) do
    ~r/%\{[^}]+\}/ |> Regex.scan(IO.iodata_to_binary(text)) |> List.flatten() |> Enum.sort()
  end
end
