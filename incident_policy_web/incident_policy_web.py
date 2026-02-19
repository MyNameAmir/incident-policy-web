import reflex as rx

from app.pages.index import index_page
from app.pages.results import results_page

app = rx.App()
app.add_page(index_page, route="/", title="Incident–Policy AI Checker")
app.add_page(results_page, route="/results", title="Results")
