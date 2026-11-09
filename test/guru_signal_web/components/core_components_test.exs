defmodule GuruSignalWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias GuruSignalWeb.CoreComponents

  test "visible inputs associate validation messages and preserve existing help text" do
    for type <- ["text", "select", "textarea", "checkbox"] do
      html =
        render_component(&CoreComponents.input/1,
          id: "field",
          name: "field",
          type: type,
          value: "",
          label: "Field",
          options: [{"Choice", "choice"}],
          errors: ["is invalid"],
          "aria-describedby": "field-help"
        )

      assert html =~ ~s(aria-invalid="true")
      assert html =~ ~s(aria-describedby="field-help field-errors")
      assert html =~ ~s(id="field-errors")
      assert html =~ "is invalid"
    end
  end

  test "valid inputs do not reference a missing error container" do
    html =
      render_component(&CoreComponents.input/1,
        id: "field",
        name: "field",
        value: "",
        label: "Field"
      )

    refute html =~ ~s(aria-invalid="true")
    refute html =~ ~s(aria-describedby=)
    refute html =~ ~s(id="field-errors")
  end
end
