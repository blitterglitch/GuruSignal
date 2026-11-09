defmodule GuruSignalWeb.Gettext do
  @moduledoc """
  Gettext backend for interface text and validation errors.

  Use `Gettext, backend: GuruSignalWeb.Gettext` in modules that render translations.
  """
  use Gettext.Backend, otp_app: :guru_signal
end
