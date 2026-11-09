defmodule GuruSignalWeb.SessionHTML do
  use GuruSignalWeb, :html

  def new(assigns) do
    ~H"""
    <main id="main-content" tabindex="-1" class="mx-auto max-w-md px-6 py-16">
      <h1 class="text-2xl font-semibold">GuruSignal owner login</h1>
      <p class="mt-2">Sign in to manage monitored endpoints.</p>
      <p :if={@error} role="alert" class="mt-4 text-error">{@error}</p>
      <.form :let={form} for={%{}} action={~p"/login"} class="mt-6 space-y-4">
        <.input
          field={form[:password]}
          type="password"
          label="Owner password"
          autocomplete="current-password"
          maxlength="1024"
          required
        />
        <button type="submit" class="btn btn-primary">Sign in</button>
      </.form>
      <.link href={~p"/"} class="mt-6 inline-block underline">Back to home</.link>
    </main>
    """
  end
end
