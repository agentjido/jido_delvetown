defmodule JidoDelvetownWeb.DashboardAccessibilityTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias JidoDelvetownWeb.DashboardComponents

  @minimum_text_contrast 4.5

  test "light and dark theme text colors meet WCAG AA contrast" do
    css = rendered_styles()
    light = theme_block(css, ~r/:root,\s*\.console-root\[data-theme="light"\]\s*\{(.*?)\}/s)
    dark = theme_block(css, ~r/\.console-root\[data-theme="dark"\]\s*\{(.*?)\}/s)

    assert_theme_text_contrast(light)
    assert_theme_text_contrast(dark)

    for {foreground, background} <- [
          {"green", "green-deep"},
          {"cyan", "cyan-deep"},
          {"amber", "amber-deep"},
          {"red", "red-deep"}
        ] do
      assert contrast(css_variable(light, foreground), css_variable(light, background)) >=
               @minimum_text_contrast

      assert contrast(css_variable(dark, foreground), css_variable(dark, background)) >=
               @minimum_text_contrast
    end
  end

  test "styles preserve keyboard focus, reduced motion, and responsive navigation" do
    css = rendered_styles()

    assert css =~ ":focus-visible"
    assert css =~ ".skip-link:focus"
    assert css =~ "outline: 3px solid var(--cyan)"
    assert css =~ "@media (prefers-reduced-motion: reduce)"
    assert css =~ "@media (max-width: 960px)"
    assert css =~ ".operator-sidebar { display: none; }"
    assert css =~ ".mobile-console-header"
    assert css =~ "@media (max-width: 520px)"
  end

  defp assert_theme_text_contrast(theme) do
    foregrounds = [
      css_variable(theme, "text"),
      css_variable(theme, "muted"),
      css_variable(theme, "quiet")
    ]

    backgrounds = [
      css_variable(theme, "canvas"),
      css_variable(theme, "surface"),
      css_variable(theme, "surface-raised"),
      css_variable(theme, "sidebar"),
      css_variable(theme, "sidebar-raised")
    ]

    for foreground <- foregrounds, background <- backgrounds do
      assert contrast(foreground, background) >= @minimum_text_contrast,
             "expected #{foreground} on #{background} to meet #{@minimum_text_contrast}:1"
    end
  end

  defp rendered_styles do
    render_component(&DashboardComponents.styles/1, %{})
  end

  defp theme_block(css, pattern) do
    assert [block] = Regex.run(pattern, css, capture: :all_but_first)
    block
  end

  defp css_variable(css, name) do
    pattern = ~r/--#{Regex.escape(name)}:\s*(#[0-9a-fA-F]{6})/
    assert [value] = Regex.run(pattern, css, capture: :all_but_first)
    value
  end

  defp contrast(first, second) do
    {lighter, darker} =
      [relative_luminance(first), relative_luminance(second)]
      |> Enum.sort(:desc)
      |> List.to_tuple()

    (lighter + 0.05) / (darker + 0.05)
  end

  defp relative_luminance("#" <> hex) do
    [0..1, 2..3, 4..5]
    |> Enum.map(fn range ->
      {channel, ""} = hex |> String.slice(range) |> Integer.parse(16)
      value = channel / 255
      if value <= 0.03928, do: value / 12.92, else: :math.pow((value + 0.055) / 1.055, 2.4)
    end)
    |> then(fn [red, green, blue] -> 0.2126 * red + 0.7152 * green + 0.0722 * blue end)
  end
end
