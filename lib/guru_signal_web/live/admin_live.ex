defmodule GuruSignalWeb.AdminLive do
  use GuruSignalWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-3xl px-6 py-16">
      <h1 class="text-2xl font-semibold">GuruSignal administration</h1>
      <p class="mt-4">Owner access is protected. Endpoint management is the next step.</p>
      <.link href={~p"/logout"} method="delete" class="mt-6 inline-block underline">
        Sign out
      </.link>
    </main>
    """
  end
end
