import reflex as rx
from reflex_base.plugins.sitemap import SitemapPlugin


config = rx.Config(
    app_name="reflex_excel_runner",
    plugins=[rx.plugins.RadixThemesPlugin()],
    disable_plugins=[SitemapPlugin],
)
