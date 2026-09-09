import reflex as rx

from .state import AppState
from .views import index


app = rx.App()
app.add_page(index, route="/", on_load=AppState.on_load)
