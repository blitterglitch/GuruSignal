defmodule GuruSignalWeb.ErrorJSON do
  @moduledoc """
  Renders HTTP status messages in the JSON error envelope.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
