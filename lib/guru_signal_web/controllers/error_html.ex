defmodule GuruSignalWeb.ErrorHTML do
  @moduledoc """
  Renders plain-text HTTP status messages for HTML error responses.
  """
  use GuruSignalWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
